import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/electricity_log_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/calculator.dart';
import '../../utils/data_refresh_bus.dart';
import '../../utils/thai_date_utils.dart';
import '../settings/settings_screen.dart'
    show openStartMeterSetup, openUtilityHistory;
import 'dashboard_styles.dart';

enum MeterKind { electricity, water }

// ผลการเช็คช่วงของเลขที่กรอก — none = ผ่าน
enum _RangeIssue { none, invalid, belowStart, belowLast }

// รายการประวัติแบบย่อ ใช้โชว์ในหน้าสำเร็จ — หน้านี้เรียกใช้ทั้งฝั่งไฟฟ้า
// และน้ำ แต่ ElectricityLogModel/WaterLogModel มีฟิลด์คนละชุด จึงแปลงเป็น
// รูปแบบย่อกลางๆ นี้ตอนเรียกใช้แทน เพื่อไม่ต้องผูกกับ 2 โมเดลพร้อมกัน
class MeterHistoryEntry {
  final DateTime date;
  final double usedFromLast;
  final double cost;

  const MeterHistoryEntry({
    required this.date,
    required this.usedFromLast,
    required this.cost,
  });
}

// ผลลัพธ์ตอนปิดหน้านี้กลับไปหน้าแดชบอร์ด — saved บอกว่ามีการบันทึกสำเร็จ
// ไหม (หน้าแดชบอร์ดใช้ตัดสินใจว่าต้องโหลดข้อมูลใหม่ไหม)
class RecordMeterResult {
  final bool saved;

  const RecordMeterResult({required this.saved});
}

// =====================================================================
// RecordMeterScreen
// =====================================================================
// หน้าเต็มจอสำหรับ "บันทึกมิเตอร์วันนี้" — ใช้กับทั้งไฟปกติ/TOU/น้ำ (ผ่าน
// MeterKind/isTou) ให้พฤติกรรมเหมือนกันหมด
//
// แบ่งเป็น 2 ขั้นตอน:
//   0) กรอก + ตรวจสอบ รวมเป็นหน้าเดียว — พิมพ์เลขมิเตอร์แล้วผลคำนวณ
//      (หน่วยที่ใช้ + ค่าใช้จ่ายประมาณการ) อัพเดทให้อัตโนมัติด้านล่าง
//      หลังหยุดพิมพ์ไปสักครู่ (debounce) ไม่ต้องกดปุ่มแยกไปหน้าตรวจสอบอีก
//      ต่างหาก — เหตุผลที่ debounce แทนคำนวณทุก keystroke: EnergyCalculator
//      อ่านอัตรา Ft จาก Firestore ทุกครั้งที่เรียก คำนวณสดทุกตัวอักษรจะยิง
//      request ถี่เกินไป
//   1) บันทึกสำเร็จ — สรุปยอด + ประวัติการบันทึกของรอบนี้
// =====================================================================
class RecordMeterScreen extends StatefulWidget {
  final MeterKind kind;
  // มิเตอร์ไฟฟ้าของผู้ใช้เป็น TOU ไหม — ช่องกรอก Peak/Off-Peak ใช้เฉพาะ
  // kind == electricity แต่ส่งต่อให้หน้าตั้งเลขมิเตอร์ต้นรอบทุก kind
  final bool isTou;
  final String uid;
  final FirestoreService firestoreService;
  final String area; // 'bangkok' หรือ 'province' — เลือกสูตร/ผู้ให้บริการ

  final double startValue; // หน่วยต้นรอบ (ไฟปกติ/น้ำ)
  // ค่าล่าสุด = เลขที่บันทึกครั้งล่าสุดในรอบบิลนี้ ถ้ารอบนี้ยังไม่ได้บันทึก
  // ผู้เรียกส่งค่าต้นรอบมาแทน (เหมือนกันทั้ง lastValue/lastPeak/lastOffPeak)
  final double lastValue;
  final double startPeak;
  final double lastPeak;
  final double startOffPeak;
  final double lastOffPeak;

  // ประวัติการบันทึกของรอบนี้ (เรียงใหม่สุดก่อน) ไม่รวมรายการที่กำลังจะ
  // บันทึกใหม่ — หน้าที่ 2 จะเอารายการที่เพิ่งบันทึกไปแปะไว้บนสุดเอง
  final List<MeterHistoryEntry> recentLogs;

  const RecordMeterScreen({
    super.key,
    required this.kind,
    this.isTou = false,
    required this.uid,
    required this.firestoreService,
    required this.area,
    this.startValue = 0,
    this.lastValue = 0,
    this.startPeak = 0,
    this.lastPeak = 0,
    this.startOffPeak = 0,
    this.lastOffPeak = 0,
    this.recentLogs = const [],
  });

  @override
  State<RecordMeterScreen> createState() => _RecordMeterScreenState();
}

class _RecordMeterScreenState extends State<RecordMeterScreen> {
  int _step = 0; // 0 = กรอก+ตรวจสอบ (รวม), 1 = สำเร็จ

  final _valueCtrl = TextEditingController();
  final _peakCtrl = TextEditingController();
  final _offPeakCtrl = TextEditingController();

  Timer? _debounce;
  bool _isCalculating = false;
  bool _previewValid = false;
  String _error = '';
  bool _isSaving = false;

  // เลขที่กรอกต้องไม่น้อยกว่าทั้งเลขต้นรอบและค่าที่บันทึกล่าสุดของรอบนี้
  // (TOU เช็คทีละช่อง) ถ้าไม่ผ่านจะบล็อกการบันทึก — ข้อความสีแดงแสดงใต้ช่อง
  // ที่ผิด ส่วนคำแนะนำ + ปุ่มด้านล่างเลือกตาม _rangeIssue (ต่ำกว่าต้นรอบ
  // มาก่อน เพราะต้องแก้ต้นรอบก่อนถึงจะเทียบกับค่าล่าสุดได้)
  _RangeIssue _rangeIssue = _RangeIssue.none;
  String _valueFieldError = '';
  String _peakFieldError = '';
  String _offPeakFieldError = '';

  bool _savedAtLeastOnce = false;

  // ผลคำนวณล่าสุด (จาก debounce หรือกดยืนยัน) — ใช้ทั้งโชว์ผลใต้ช่องกรอก
  // และใช้บันทึกจริงตอนกดยืนยัน (ไม่คำนวณซ้ำตอนบันทึก)
  double _previewPeakValue = 0;
  double _previewOffPeakValue = 0;
  double _previewNormalValue = 0;
  double _previewUsedFromStart = 0;
  double _previewUsedFromLast = 0;
  double _previewCost = 0;

  // ผลลัพธ์หลังบันทึกสำเร็จ — โชว์ในขั้นตอนที่ 1
  double _savedUsedFromStart = 0;
  double _savedCost = 0;
  DateTime _savedAt = DateTime.now();
  List<MeterHistoryEntry> _historyAfterSave = const [];

  bool get _isTouElectricity =>
      widget.kind == MeterKind.electricity && widget.isTou;

  Color get _accent => widget.kind == MeterKind.electricity
      ? DashboardStyles.electricityBorder
      : DashboardStyles.waterBorder;

  // เฉดเข้มกว่า _accent สำหรับตัวเลขเน้นในแบนเนอร์ค่าใช้จ่ายประมาณการ
  // (คำนวณจากสี _accent ของยูทิลิตี้นั้นๆ เอง ทั้งไฟฟ้าและน้ำ)
  Color get _darkAccent => Color.alphaBlend(Colors.black.withValues(alpha: 0.3), _accent);

  String get _unit => widget.kind == MeterKind.electricity ? 'หน่วย' : 'ลบ.ม.';

  String get _utilityLabel =>
      widget.kind == MeterKind.electricity ? 'ไฟฟ้า' : 'น้ำ';

  // ชื่อย่อหน่วยงานตามพื้นที่ — ใช้แค่ประกอบข้อความอ้างอิงอัตรา
  String get _providerLabel {
    final isBangkok = widget.area == 'bangkok';
    if (widget.kind == MeterKind.electricity) {
      return isBangkok ? 'กฟน.' : 'กฟภ.';
    }
    return isBangkok ? 'กปน.' : 'กปภ.';
  }

  @override
  void initState() {
    super.initState();
    _valueCtrl.addListener(_scheduleCalc);
    _peakCtrl.addListener(_scheduleCalc);
    _offPeakCtrl.addListener(_scheduleCalc);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _valueCtrl.dispose();
    _peakCtrl.dispose();
    _offPeakCtrl.dispose();
    super.dispose();
  }


  // เรียกทุกครั้งที่พิมพ์ในช่องกรอก — ยกเลิก timer เดิม ตั้งใหม่ให้รอ
  // 500ms หลังหยุดพิมพ์ค่อยคำนวณจริง (debounce กัน Firestore read ถี่)
  void _scheduleCalc() {
    setState(() {
      _isCalculating = true;
      _previewValid = false;
      _error = '';
      _resetRangeFlags();
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _runCalc());
  }

  void _resetRangeFlags() {
    _rangeIssue = _RangeIssue.none;
    _valueFieldError = '';
    _peakFieldError = '';
    _offPeakFieldError = '';
  }

  // เช็คข้อความที่กรอก 1 ช่อง — แปลงเป็นตัวเลข แล้วเทียบกับต้นรอบ/ค่าล่าสุด
  // คืนค่าที่ใช้คำนวณ + issue ของช่องนั้น + ข้อความ (ว่าง = ผ่าน)
  // ช่องว่างใช้ค่า fallback แทน (TOU เว้นช่องได้ = ช่วงนั้นไม่ได้ใช้เพิ่ม)
  // label ว่าง = มิเตอร์ปกติ/น้ำ
  ({double value, _RangeIssue issue, String message}) _checkField({
    required String label,
    required String text,
    required double fallback,
    required double start,
    required double last,
  }) {
    if (text.trim().isEmpty) {
      return (value: fallback, issue: _RangeIssue.none, message: '');
    }
    final value = double.tryParse(text.replaceAll(',', '').trim());
    if (value == null) {
      return (
        value: 0,
        issue: _RangeIssue.invalid,
        message: 'รูปแบบตัวเลขไม่ถูกต้อง กรุณากรอกเฉพาะตัวเลขค่ะ',
      );
    }

    final formatter = NumberFormat('#,##0.##');
    final subject = label.isEmpty ? 'เลขมิเตอร์' : 'เลข $label';
    if (value < start) {
      return (
        value: value,
        issue: _RangeIssue.belowStart,
        message:
            '$subjectต้องไม่น้อยกว่าเลขต้นรอบบิล (${formatter.format(start)} $_unit) ค่ะ',
      );
    }
    if (value < last) {
      return (
        value: value,
        issue: _RangeIssue.belowLast,
        message:
            '$subjectต้องไม่น้อยกว่าค่าที่บันทึกล่าสุด (${formatter.format(last)} $_unit) ค่ะ',
      );
    }
    return (value: value, issue: _RangeIssue.none, message: '');
  }

  // เลือกคำแนะนำ + ปุ่มด้านล่างจาก issue ของทุกช่อง — ต่ำกว่าต้นรอบมาก่อน
  // (ต้องแก้ต้นรอบก่อนถึงจะเทียบกับค่าล่าสุดได้) ส่วน invalid ไม่มีคำแนะนำ
  // เพิ่ม เพราะข้อความใต้ช่องบอกวิธีแก้อยู่แล้ว
  _RangeIssue _helpIssueOf(List<_RangeIssue> issues) {
    if (issues.contains(_RangeIssue.belowStart)) return _RangeIssue.belowStart;
    if (issues.contains(_RangeIssue.belowLast)) return _RangeIssue.belowLast;
    return _RangeIssue.none;
  }

  // คำนวณผลลัพธ์จากค่าที่กรอกตอนนี้ — ใช้ทั้งตอน debounce (showEmptyError:
  // false ไม่บ่นถ้ายังกรอกไม่ครบ) และตอนกดยืนยันบันทึก (showEmptyError:
  // true ต้องเตือนถ้ายังไม่กรอกอะไรเลย)
  Future<void> _runCalc({bool showEmptyError = false}) async {
    if (_isTouElectricity) {
      final peakEmpty = _peakCtrl.text.trim().isEmpty;
      final offPeakEmpty = _offPeakCtrl.text.trim().isEmpty;
      if (peakEmpty && offPeakEmpty) {
        if (mounted) {
          setState(() {
            _isCalculating = false;
            _previewValid = false;
            _resetRangeFlags();
            _error = showEmptyError
                ? 'กรุณากรอกเลขมิเตอร์ On-Peak (T1) หรือ Off-Peak (T2) อย่างน้อย 1 ช่องค่ะ'
                : '';
          });
        }
        return;
      }

      final peakCheck = _checkField(
        label: 'On-Peak (T1)',
        text: _peakCtrl.text,
        fallback: widget.lastPeak,
        start: widget.startPeak,
        last: widget.lastPeak,
      );
      final offPeakCheck = _checkField(
        label: 'Off-Peak (T2)',
        text: _offPeakCtrl.text,
        fallback: widget.lastOffPeak,
        start: widget.startOffPeak,
        last: widget.lastOffPeak,
      );
      if (peakCheck.issue != _RangeIssue.none ||
          offPeakCheck.issue != _RangeIssue.none) {
        if (mounted) {
          setState(() {
            _isCalculating = false;
            _previewValid = false;
            _error = '';
            _resetRangeFlags();
            _peakFieldError = peakCheck.message;
            _offPeakFieldError = offPeakCheck.message;
            _rangeIssue = _helpIssueOf([peakCheck.issue, offPeakCheck.issue]);
          });
        }
        return;
      }
      final peakValue = peakCheck.value;
      final offPeakValue = offPeakCheck.value;

      final peakUnits = EnergyCalculator.calculateUsed(peakValue, widget.startPeak);
      final offPeakUnits =
          EnergyCalculator.calculateUsed(offPeakValue, widget.startOffPeak);
      final usedFromStart = peakUnits + offPeakUnits;
      final usedFromLast =
          EnergyCalculator.calculateUsed(peakValue, widget.lastPeak) +
              EnergyCalculator.calculateUsed(offPeakValue, widget.lastOffPeak);

      final cost = await EnergyCalculator.calculateElectricityByType(
        units: 0,
        meterType: 'tou',
        area: widget.area,
        peakUnits: peakUnits,
        offPeakUnits: offPeakUnits,
      );

      if (!mounted) return;
      setState(() {
        _previewPeakValue = peakValue;
        _previewOffPeakValue = offPeakValue;
        _previewUsedFromStart = usedFromStart;
        _previewUsedFromLast = usedFromLast;
        _previewCost = cost;
        _previewValid = true;
        _isCalculating = false;
        _error = '';
        _resetRangeFlags();
      });
      return;
    }

    if (_valueCtrl.text.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _previewValid = false;
          _resetRangeFlags();
          _error = showEmptyError ? 'กรุณากรอกเลขมิเตอร์$_utilityLabelก่อนบันทึกค่ะ' : '';
        });
      }
      return;
    }
    // ไม่ต้องเช็ค <= 0 แยก — ค่าติดลบหรือ 0 จะไม่ผ่านการเทียบกับต้นรอบเอง
    // (ยกเว้นต้นรอบเป็น 0 ซึ่งการบันทึก 0 ก็แปลว่ายังไม่ได้ใช้ ถือว่าถูกต้อง)
    final check = _checkField(
      label: '',
      text: _valueCtrl.text,
      fallback: widget.lastValue,
      start: widget.startValue,
      last: widget.lastValue,
    );
    if (check.issue != _RangeIssue.none) {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _previewValid = false;
          _error = '';
          _resetRangeFlags();
          _valueFieldError = check.message;
          _rangeIssue = _helpIssueOf([check.issue]);
        });
      }
      return;
    }
    final value = check.value;

    final usedFromStart = EnergyCalculator.calculateUsed(value, widget.startValue);
    final usedFromLast = EnergyCalculator.calculateUsed(value, widget.lastValue);

    double cost;
    if (widget.kind == MeterKind.electricity) {
      cost = await EnergyCalculator.calculateElectricityByType(
        units: usedFromStart,
        meterType: 'normal',
        area: widget.area,
      );
    } else {
      cost = EnergyCalculator.calculateWater(usedFromStart, widget.area);
    }

    if (!mounted) return;
    setState(() {
      _previewNormalValue = value;
      _previewUsedFromStart = usedFromStart;
      _previewUsedFromLast = usedFromLast;
      _previewCost = cost;
      _previewValid = true;
      _isCalculating = false;
      _error = '';
      _resetRangeFlags();
    });
  }

  // กดปุ่ม "ยืนยันบันทึก" — ยกเลิก debounce ที่ค้างอยู่แล้วบังคับคำนวณ
  // ทันที (เผื่อผู้ใช้พิมพ์เสร็จแล้วรีบกดก่อนครบ 500ms) จากนั้นค่อยบันทึก
  // จริงถ้าค่าที่ได้ถูกต้อง
  Future<void> _onConfirmTap() async {
    _debounce?.cancel();
    setState(() => _isCalculating = true);
    await _runCalc(showEmptyError: true);
    if (!_previewValid || !mounted) return;
    await _doSave();
  }

  // เปิดหน้าตั้งเลขมิเตอร์ต้นรอบ หรือหน้าประวัติการบันทึกมิเตอร์ (ตัวเดียวกับ
  // ที่หน้าอื่นใช้) — ถ้ามีการแก้ข้อมูลระหว่างนั้น (DataRefreshBus เปลี่ยน)
  // ค่าต้นรอบ/ล่าสุดที่หน้านี้ถืออยู่จะไม่ตรงแล้ว จึงปิดกลับไปแดชบอร์ดให้
  // โหลดข้อมูลใหม่ก่อนบันทึก
  Future<void> _openAndReturnIfChanged(Future<void> Function() open) async {
    final versionBefore = DataRefreshBus.instance.version.value;
    await open();
    if (!mounted) return;
    if (DataRefreshBus.instance.version.value != versionBefore) {
      _closeWith(true);
    }
  }

  Future<void> _openStartMeterSetup() => _openAndReturnIfChanged(() =>
      openStartMeterSetup(context, widget.uid, widget.firestoreService, widget.isTou));

  Future<void> _openUtilityHistory() => _openAndReturnIfChanged(() => openUtilityHistory(
        context,
        widget.uid,
        widget.firestoreService,
        initialTab: widget.kind == MeterKind.electricity ? 0 : 1,
      ));

  Future<void> _doSave() async {
    setState(() => _isSaving = true);
    try {
      if (widget.kind == MeterKind.electricity) {
        final log = ElectricityLogModel(
          id: const Uuid().v4(),
          uid: widget.uid,
          date: DateTime.now(),
          meterValue: _isTouElectricity ? _previewUsedFromStart : _previewNormalValue,
          peakMeterValue: _isTouElectricity ? _previewPeakValue : null,
          offPeakMeterValue: _isTouElectricity ? _previewOffPeakValue : null,
          usedFromStart: _previewUsedFromStart,
          usedFromLast: _previewUsedFromLast,
          cost: _previewCost,
        );
        await widget.firestoreService.saveElectricityLog(log);
      } else {
        final log = WaterLogModel(
          id: const Uuid().v4(),
          uid: widget.uid,
          date: DateTime.now(),
          meterValue: _previewNormalValue,
          usedFromStart: _previewUsedFromStart,
          usedFromLast: _previewUsedFromLast,
          cost: _previewCost,
        );
        await widget.firestoreService.saveWaterLog(log);
      }

      _savedUsedFromStart = _previewUsedFromStart;
      _savedCost = _previewCost;
      _savedAt = DateTime.now();
      _historyAfterSave = [
        MeterHistoryEntry(
            date: _savedAt, usedFromLast: _previewUsedFromLast, cost: _previewCost),
        ...widget.recentLogs,
      ];

      if (mounted) {
        setState(() {
          _savedAtLeastOnce = true;
          _step = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'บันทึกข้อมูลไม่สำเร็จ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _closeWith(bool saved) {
    Navigator.pop(context, RecordMeterResult(saved: saved || _savedAtLeastOnce));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeWith(false);
      },
      child: Scaffold(
        backgroundColor: DashboardStyles.background,
        appBar: AppBar(
          backgroundColor: _accent,
          elevation: 0,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          automaticallyImplyLeading: false,
          leadingWidth: 56,
          leading: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.v8),
            child: Center(
              child: InkWell(
                onTap: () => _closeWith(false),
                borderRadius: BorderRadius.circular(AppSpacing.v20),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(Icons.chevron_left, size: 26, color: Colors.white),
                ),
              ),
            ),
          ),
          title: _step == 0
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppSpacing.v2),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 22,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(AppSpacing.v2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('บันทึกมิเตอร์$_utilityLabel',
                        style: const TextStyle(fontSize: AppTypography.s15, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                )
              : const Text('บันทึกสำเร็จ', style: TextStyle(color: Colors.white)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.v20),
            child: _step == 0 ? _buildEntryAndConfirmStep() : _buildSuccessStep(),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // ขั้นตอน 0 — กรอก + ผลคำนวณสด (รวมกันเป็นหน้าเดียว)
  // =====================================================================
  Widget _buildEntryAndConfirmStep() {
    final formatter = NumberFormat('#,##0.##');
    final costFormatter = NumberFormat('#,##0.00');

    InputDecoration decoration(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: DashboardStyles.hintStyle,
          suffixText: _unit,
          isDense: true,
          filled: true,
          fillColor: DashboardStyles.background,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.v16, vertical: AppSpacing.v14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.v12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.v12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.v12),
            borderSide: BorderSide(color: _accent, width: 1.6),
          ),
        );

    // lastIsPlaceholder = true เมื่อยังไม่เคยบันทึกมิเตอร์เลยในรอบนี้ (เพิ่งตั้ง
    // ต้นรอบใหม่ผ่านหน้าตั้งค่า) — ตอนนั้น "ค่าล่าสุด" ที่โชว์จริงๆ คือค่าต้นรอบ
    // เอง (fallback) ไม่ใช่ค่าที่กรอกจริง จึงทำให้จางลงกันสับสนว่าเป็นค่าจริง
    // พอบันทึกมิเตอร์ครั้งแรกของรอบนี้แล้ว (recentLogs ไม่ว่าง) ค่อยกลับมาเข้มปกติ
    Widget lastValueChips(double last, double start, {bool lastIsPlaceholder = false}) {
      final lastTextColor = lastIsPlaceholder ? Colors.grey.shade400 : null;
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v10, vertical: AppSpacing.v7),
              decoration: BoxDecoration(
                color: DashboardStyles.background,
                borderRadius: BorderRadius.circular(AppSpacing.v8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history, size: 11, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Text('ค่าล่าสุด', style: TextStyle(fontSize: AppTypography.s10, color: Colors.grey.shade600)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${formatter.format(last)} $_unit',
                      style: TextStyle(
                          fontSize: AppTypography.s13,
                          fontWeight: lastIsPlaceholder ? FontWeight.w400 : FontWeight.w600,
                          color: lastTextColor)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v10, vertical: AppSpacing.v7),
              decoration: BoxDecoration(
                color: DashboardStyles.background,
                borderRadius: BorderRadius.circular(AppSpacing.v8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.outlined_flag, size: 11, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Text('ต้นรอบ', style: TextStyle(fontSize: AppTypography.s10, color: Colors.grey.shade600)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${formatter.format(start)} $_unit',
                      style: TextStyle(
                          fontSize: AppTypography.s13,
                          fontWeight: lastIsPlaceholder ? FontWeight.w600 : FontWeight.w400,
                          color: lastIsPlaceholder ? null : Colors.grey.shade400)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    Widget fieldCard({
      required IconData icon,
      required String label,
      required TextEditingController controller,
      required double last,
      required double start,
      bool autofocus = false,
      double fontSize = 22,
      bool lastIsPlaceholder = false,
      String fieldError = '',
    }) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.v14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 0.6),
          borderRadius: BorderRadius.circular(AppSpacing.v14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.v7),
                  ),
                  child: Icon(icon, size: 13, color: _accent),
                ),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.s12_5, color: _accent)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: autofocus,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
              decoration: decoration('เช่น 12,345'),
            ),
            if (fieldError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.v6),
                child: Text(fieldError,
                    style: const TextStyle(color: Colors.red, fontSize: AppTypography.s12)),
              ),
            const SizedBox(height: 8),
            lastValueChips(last, start, lastIsPlaceholder: lastIsPlaceholder),
          ],
        ),
      );
    }

    Widget calculationPanel() {
      return AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _previewValid ? 1 : 0.35,
        child: IgnorePointer(
          ignoring: !_previewValid,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.v14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300, width: 0.6),
                  borderRadius: BorderRadius.circular(AppSpacing.v14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: DashboardStyles.primaryGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppSpacing.v7),
                          ),
                          child: const Icon(Icons.calculate_outlined,
                              size: 13, color: DashboardStyles.primaryGreen),
                        ),
                        const SizedBox(width: 8),
                        const Text('การคำนวณ',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.s14)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_isTouElectricity) ...[
                      _calcRow('รวมมิเตอร์วันนี้ (Peak+Off-Peak)',
                          '${formatter.format(_previewPeakValue + _previewOffPeakValue)} $_unit'),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.v4),
                          child: Icon(Icons.remove, size: 13, color: Colors.grey.shade400),
                        ),
                      ),
                      _calcRow('รวมต้นรอบบิล',
                          '${formatter.format(widget.startPeak + widget.startOffPeak)} $_unit'),
                    ] else ...[
                      _calcRow('มิเตอร์วันนี้', '${formatter.format(_previewNormalValue)} $_unit'),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.v4),
                          child: Icon(Icons.remove, size: 13, color: Colors.grey.shade400),
                        ),
                      ),
                      _calcRow('ต้นรอบบิล', '${formatter.format(widget.startValue)} $_unit'),
                    ],
                    const Divider(height: 20),
                    _calcRow('ใช้ไปในรอบนี้', '${formatter.format(_previewUsedFromStart)} $_unit',
                        bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.v14),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.v14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text('฿',
                          style: TextStyle(fontSize: AppTypography.s14, fontWeight: FontWeight.bold, color: _accent)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ค่า$_utilityLabelโดยประมาณ (ถึงวันนี้)\nอ้างอิงอัตราปัจจุบันของ $_providerLabel',
                        style: TextStyle(fontSize: AppTypography.s12, height: 1.4, color: _accent),
                      ),
                    ),
                    Text('฿${costFormatter.format(_previewCost)}',
                        style: TextStyle(
                            fontSize: AppTypography.s20, fontWeight: FontWeight.bold, color: _darkAccent)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isTouElectricity) ...[
            fieldCard(
              icon: Icons.wb_sunny_outlined,
              label: 'On-Peak (T1)',
              controller: _peakCtrl,
              last: widget.lastPeak,
              start: widget.startPeak,
              autofocus: true,
              lastIsPlaceholder: widget.recentLogs.isEmpty,
              fieldError: _peakFieldError,
            ),
            const SizedBox(height: 10),
            fieldCard(
              icon: Icons.nightlight_outlined,
              label: 'Off-Peak (T2)',
              controller: _offPeakCtrl,
              last: widget.lastOffPeak,
              start: widget.startOffPeak,
              lastIsPlaceholder: widget.recentLogs.isEmpty,
              fieldError: _offPeakFieldError,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('หากช่วงเวลาใดยังไม่มีการใช้ไฟเพิ่ม เว้นช่องนั้นว่างไว้ได้ ระบบจะใช้ค่าล่าสุดแทนค่ะ',
                      style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
                ),
              ],
            ),
          ] else ...[
            fieldCard(
              icon: widget.kind == MeterKind.electricity ? Icons.bolt : Icons.water_drop,
              label: 'ค่ามิเตอร์$_utilityLabelสะสม',
              controller: _valueCtrl,
              last: widget.lastValue,
              start: widget.startValue,
              autofocus: true,
              fontSize: AppTypography.s26,
              lastIsPlaceholder: widget.recentLogs.isEmpty,
              fieldError: _valueFieldError,
            ),
          ],
          const SizedBox(height: 14),
          if (_isCalculating)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.v10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                  ),
                  const SizedBox(width: 8),
                  Text('กำลังคำนวณ...',
                      style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
                ],
              ),
            ),
          calculationPanel(),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.v14),
              child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: AppTypography.s12_5)),
            ),
          if (_rangeIssue == _RangeIssue.belowStart)
            _rangeIssueHelp(
              message: 'หากเพิ่งเปลี่ยนมิเตอร์ใหม่ กรุณาตั้งเลขมิเตอร์ต้นรอบใหม่ก่อนบันทึกค่ะ',
              buttonIcon: Icons.refresh,
              buttonLabel: 'ตั้งเลขมิเตอร์ต้นรอบใหม่',
              onPressed: _openStartMeterSetup,
            ),
          if (_rangeIssue == _RangeIssue.belowLast)
            _rangeIssueHelp(
              message: 'หากตรวจสอบแล้วว่าเลขที่กรอกถูกต้อง แสดงว่าการบันทึกครั้งล่าสุด'
                  'อาจคลาดเคลื่อน กรุณาลบรายการดังกล่าวที่ ตั้งค่า › ประวัติการบันทึกมิเตอร์ '
                  'แล้วจึงบันทึกเลขนี้อีกครั้งค่ะ',
              buttonIcon: Icons.history,
              buttonLabel: 'ไปที่ประวัติการบันทึกมิเตอร์',
              onPressed: _openUtilityHistory,
            ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _onConfirmTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.v14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v12)),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_isSaving ? 'กำลังบันทึก...' : 'ยืนยันบันทึก'),
          ),
        ],
      ),
    );
  }

  // คำแนะนำ + ปุ่มแก้ไข ใต้ข้อความแดงเมื่อเลขที่กรอกไม่ผ่านการเช็คช่วง
  Widget _rangeIssueHelp({
    required String message,
    required IconData buttonIcon,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.v14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message,
              style: TextStyle(fontSize: AppTypography.s12, height: 1.5, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSaving ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(color: _accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.v10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v10)),
            ),
            icon: Icon(buttonIcon, size: 16),
            label: Text(buttonLabel, style: const TextStyle(fontSize: AppTypography.s12_5)),
          ),
        ],
      ),
    );
  }

  Widget _calcRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade700)),
        Text(value,
            style: TextStyle(
              fontSize: bold ? AppTypography.s15 : AppTypography.s13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: bold ? _accent : DashboardStyles.textDark,
            )),
      ],
    );
  }

  // =====================================================================
  // ขั้นตอน 1 — บันทึกสำเร็จ + ประวัติของรอบนี้
  // =====================================================================
  String _shortThaiDate(DateTime d) {
    final month = thaiMonths[d.month - 1];
    final shortMonth = month.length > 3 ? '${month.substring(0, 3)}.' : month;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} $shortMonth ${(d.year + 543) % 100} • $hh:$mm น.';
  }

  Widget _buildSuccessStep() {
    final formatter = NumberFormat('#,##0.##');
    final costFormatter = NumberFormat('#,##0.00');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.v14),
                  decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 12),
                const Text('บันทึกสำเร็จ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.s18)),
                Text(_shortThaiDate(_savedAt), style: DashboardStyles.lastValueStyle),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.v16),
            decoration: DashboardStyles.whiteCard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ใช้ไปในรอบนี้ (อัปเดตแล้ว)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.s13_5, color: _accent)),
                const SizedBox(height: 10),
                _calcRow('ใช้ไปในรอบนี้', '${formatter.format(_savedUsedFromStart)} $_unit', bold: true),
                const SizedBox(height: 4),
                _calcRow('ค่า$_utilityLabelโดยประมาณ', '฿${costFormatter.format(_savedCost)}', bold: true),
              ],
            ),
          ),
          if (_historyAfterSave.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('ประวัติการบันทึกรอบนี้', style: DashboardStyles.sectionTitle),
            const SizedBox(height: 8),
            ..._historyAfterSave.take(5).map((e) {
              final isLatest = e == _historyAfterSave.first;
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.v8),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v14, vertical: AppSpacing.v10),
                decoration: DashboardStyles.whiteCard(radius: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(_shortThaiDate(e.date), style: const TextStyle(fontSize: AppTypography.s12_5)),
                        if (isLatest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v6, vertical: AppSpacing.v2),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppSpacing.v6),
                            ),
                            child: Text('ล่าสุด', style: TextStyle(fontSize: AppTypography.s10, color: _accent)),
                          ),
                        ],
                      ],
                    ),
                    Text('+${formatter.format(e.usedFromLast)} $_unit • ฿${costFormatter.format(e.cost)}',
                        style: const TextStyle(fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _closeWith(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.v14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v12)),
              ),
              child: const Text('กลับหน้าหลัก'),
            ),
          ),
        ],
      ),
    );
  }
}