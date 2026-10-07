import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/electricity_log_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/calculator.dart';
import '../../utils/data_refresh_bus.dart';
import '../../utils/meter_reading_check.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/ui/animated_amount.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/fade_slide_in.dart';
import '../../widgets/ui/icon_badge.dart';
import '../settings/settings_screen.dart'
    show openInvoiceScreen, openUtilityHistory;
import 'dashboard_styles.dart';

enum MeterKind { electricity, water }

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
  // ประเภทอัตราค่าไฟของมิเตอร์ปกติ (UserModel.electricityTariff) ไม่มีผลกับ TOU
  final String tariff;

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
    this.tariff = EnergyCalculator.tariffStandard,
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
  MeterRangeIssue _rangeIssue = MeterRangeIssue.none;
  String _valueFieldError = '';
  String _peakFieldError = '';
  String _offPeakFieldError = '';

  // มีช่องที่เลขไม่ผ่านการเช็ค (ต่ำกว่าต้นรอบ/ค่าล่าสุด หรือไม่ใช่ตัวเลข) —
  // ปิดปุ่มบันทึกไว้จนกว่าจะพิมพ์แก้ (การพิมพ์จะล้างสถานะนี้ทันที) ส่วนช่อง
  // ว่างยังกดได้ เพื่อให้ขึ้นข้อความบอกว่าต้องกรอกอะไรก่อน
  bool get _hasFieldError =>
      _valueFieldError.isNotEmpty ||
      _peakFieldError.isNotEmpty ||
      _offPeakFieldError.isNotEmpty;

  bool _savedAtLeastOnce = false;

  // เปิด/ปิดส่วน "ดูวิธีคำนวณ" ในการ์ดสรุป (ยุบไว้เป็นค่าเริ่มต้น)
  bool _showCalcDetail = false;

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
    _rangeIssue = MeterRangeIssue.none;
    _valueFieldError = '';
    _peakFieldError = '';
    _offPeakFieldError = '';
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

      final peakCheck = MeterReadingCheck.check(
        unit: _unit,
        label: 'On-Peak (T1)',
        text: _peakCtrl.text,
        fallback: widget.lastPeak,
        start: widget.startPeak,
        last: widget.lastPeak,
      );
      final offPeakCheck = MeterReadingCheck.check(
        unit: _unit,
        label: 'Off-Peak (T2)',
        text: _offPeakCtrl.text,
        fallback: widget.lastOffPeak,
        start: widget.startOffPeak,
        last: widget.lastOffPeak,
      );
      if (peakCheck.issue != MeterRangeIssue.none ||
          offPeakCheck.issue != MeterRangeIssue.none) {
        if (mounted) {
          setState(() {
            _isCalculating = false;
            _previewValid = false;
            _error = '';
            _resetRangeFlags();
            _peakFieldError = peakCheck.message;
            _offPeakFieldError = offPeakCheck.message;
            _rangeIssue = MeterReadingCheck.helpIssueOf([peakCheck.issue, offPeakCheck.issue]);
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
    final check = MeterReadingCheck.check(
      unit: _unit,
      label: '',
      text: _valueCtrl.text,
      fallback: widget.lastValue,
      start: widget.startValue,
      last: widget.lastValue,
    );
    if (check.issue != MeterRangeIssue.none) {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _previewValid = false;
          _error = '';
          _resetRangeFlags();
          _valueFieldError = check.message;
          _rangeIssue = MeterReadingCheck.helpIssueOf([check.issue]);
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
        tariff: widget.tariff,
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
      openInvoiceScreen(context, widget.uid, widget.firestoreService));

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
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'กลับ',
            onPressed: () => _closeWith(false),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          title: Text(_step == 0 ? 'บันทึกมิเตอร์$_utilityLabel' : 'บันทึกสำเร็จ'),
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _step == 0
                ? KeyedSubtree(key: const ValueKey(0), child: _buildEntryStep())
                : KeyedSubtree(key: const ValueKey(1), child: _buildSuccessStep()),
          ),
        ),
      ),
    );
  }

  static final _unitFormatter = NumberFormat('#,##0.##');
  static final _costFormatter = NumberFormat('#,##0.00');

  // ตัวเลขกว้างเท่ากันทุกหลัก — เลขมิเตอร์/หน่วยเรียงตรงกันและไม่กระตุกตอนพิมพ์
  static const _tabular = [FontFeature.tabularFigures()];

  // วันที่สั้น เช่น "5 ต.ค. 69" (+ เวลา ถ้า withTime)
  String _shortThaiDate(DateTime d, {bool withTime = true}) {
    final date = '${d.day} ${thaiMonthsShort[d.month - 1]} ${(d.year + 543) % 100}';
    if (!withTime) return date;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$date • $hh:$mm น.';
  }

  // พื้นที่เนื้อหาเลื่อนได้ + ปุ่มหลักติดขอบล่าง (อยู่เหนือคีย์บอร์ดเสมอ
  // เพราะ body ของ Scaffold หดตามคีย์บอร์ด)
  Widget _scrollWithBottomButton({required List<Widget> children, required Widget button}) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v16, AppSpacing.v20, AppSpacing.v24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v12, AppSpacing.v20, AppSpacing.v16),
          decoration: BoxDecoration(
            color: DashboardStyles.background,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: button,
        ),
      ],
    );
  }

  ButtonStyle get _primaryButtonStyle => ElevatedButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _accent.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
      );

  // =====================================================================
  // ขั้นตอน 0 — กรอก + ผลคำนวณสด (รวมกันเป็นหน้าเดียว)
  // =====================================================================
  // ระหว่างพิมพ์ ผู้ใช้ต้องการตัวเทียบแค่ตัวเดียวว่าเลขที่อ่านได้สมเหตุสมผลไหม
  // จึงแสดงเฉพาะเลขครั้งก่อน (หรือเลขต้นรอบ ถ้ารอบนี้ยังไม่เคยจด) เป็นบรรทัด
  // เล็กใต้ช่อง ส่วนสูตรคำนวณ/หน่วยแยกช่วงเวลา/อัตราที่อ้างอิง ยุบไว้ใต้
  // "ดูวิธีคำนวณ" สำหรับผู้ที่อยากตรวจสอบ
  Widget _buildEntryStep() {
    // ยังไม่เคยบันทึกในรอบนี้ (เพิ่งตั้งต้นรอบใหม่) — ค่า last ที่ส่งมาคือ
    // ค่าต้นรอบ (fallback) ไม่ใช่เลขที่จดจริง
    final hasLast = widget.recentLogs.isNotEmpty;

    return _scrollWithBottomButton(
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.v16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: widget.kind == MeterKind.electricity ? Icons.bolt_rounded : Icons.water_drop_rounded,
                    color: _accent,
                    size: 32,
                  ),
                  const SizedBox(width: AppSpacing.v10),
                  Expanded(
                    child: Text('เลขบนมิเตอร์$_utilityLabelวันนี้',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: AppTypography.s14, color: AppColors.textDark)),
                  ),
                  Text(_shortThaiDate(DateTime.now(), withTime: false),
                      style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: AppSpacing.v14),
              if (_isTouElectricity) ...[
                _meterField(
                  label: 'On-Peak (T1)',
                  icon: Icons.wb_sunny_outlined,
                  controller: _peakCtrl,
                  last: widget.lastPeak,
                  start: widget.startPeak,
                  hasLast: hasLast,
                  autofocus: true,
                  fieldError: _peakFieldError,
                ),
                const SizedBox(height: AppSpacing.v16),
                _meterField(
                  label: 'Off-Peak (T2)',
                  icon: Icons.nightlight_outlined,
                  controller: _offPeakCtrl,
                  last: widget.lastOffPeak,
                  start: widget.startOffPeak,
                  hasLast: hasLast,
                  fieldError: _offPeakFieldError,
                ),
                const SizedBox(height: AppSpacing.v12),
                Text('ช่องไหนยังไม่ได้ใช้ไฟเพิ่ม เว้นว่างไว้ได้ค่ะ',
                    style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
              ] else
                _meterField(
                  controller: _valueCtrl,
                  last: widget.lastValue,
                  start: widget.startValue,
                  hasLast: hasLast,
                  autofocus: true,
                  fieldError: _valueFieldError,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.v16),
        _resultCard(hasLast: hasLast),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.v14),
            child: _errorLine(_error),
          ),
        if (_rangeIssue == MeterRangeIssue.belowStart)
          _rangeIssueHelp(
            message: 'หากเพิ่งเปลี่ยนมิเตอร์ใหม่ กรุณาตั้งเลขมิเตอร์ต้นรอบใหม่ก่อนบันทึกค่ะ',
            buttonIcon: Icons.refresh_rounded,
            buttonLabel: 'ตั้งเลขมิเตอร์ต้นรอบใหม่',
            onPressed: _openStartMeterSetup,
          ),
        if (_rangeIssue == MeterRangeIssue.belowLast)
          _rangeIssueHelp(
            message: 'หากตรวจสอบแล้วว่าเลขที่กรอกถูกต้อง แสดงว่าการบันทึกครั้งล่าสุด'
                'อาจคลาดเคลื่อน กรุณาลบรายการดังกล่าวที่ ตั้งค่า › ประวัติการบันทึกมิเตอร์ '
                'แล้วจึงบันทึกเลขนี้อีกครั้งค่ะ',
            buttonIcon: Icons.history_rounded,
            buttonLabel: 'ไปที่ประวัติการบันทึกมิเตอร์',
            onPressed: _openUtilityHistory,
          ),
      ],
      button: ElevatedButton.icon(
        onPressed: (_isSaving || _hasFieldError) ? null : _onConfirmTap,
        style: _primaryButtonStyle,
        icon: _isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.check_rounded, size: 20),
        label: Text(_isSaving ? 'กำลังบันทึก...' : 'ยืนยันบันทึก'),
      ),
    );
  }

  // ช่องกรอก 1 ช่อง + บรรทัดตัวเทียบใต้ช่อง (เลขครั้งก่อน หรือเลขต้นรอบถ้า
  // รอบนี้ยังไม่เคยจด) — ถ้าเลขไม่ผ่านการเช็ค ข้อความผิดพลาดจะแทนที่บรรทัด
  // ตัวเทียบ (ข้อความบอกเลขที่ต้องไม่น้อยกว่าอยู่แล้ว) [label] ใช้เฉพาะ TOU
  Widget _meterField({
    String? label,
    IconData? icon,
    required TextEditingController controller,
    required double last,
    required double start,
    required bool hasLast,
    bool autofocus = false,
    String fieldError = '',
  }) {
    final hasError = fieldError.isNotEmpty;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      borderSide: hasError ? BorderSide(color: Colors.red.shade300, width: 1.2) : BorderSide.none,
    );
    final reference = hasLast
        ? 'ครั้งก่อน ${_unitFormatter.format(last)} $_unit · '
            '${_shortThaiDate(widget.recentLogs.first.date, withTime: false)}'
        : 'เลขมิเตอร์ต้นรอบ ${_unitFormatter.format(start)} $_unit';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: _accent),
                const SizedBox(width: AppSpacing.v6),
              ],
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.s13, color: _darkAccent)),
            ],
          ),
          const SizedBox(height: AppSpacing.v6),
        ],
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          cursorColor: _accent,
          style: TextStyle(
            fontSize: _isTouElectricity ? AppTypography.s24 : AppTypography.s32,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.textDark,
            fontFeatures: _tabular,
          ),
          decoration: InputDecoration(
            hintText: 'เช่น 12,345',
            hintStyle: TextStyle(
                fontSize: AppTypography.s18, fontWeight: FontWeight.w500, color: Colors.grey.shade400),
            suffixText: _unit,
            suffixStyle: TextStyle(fontSize: AppTypography.s14, color: Colors.grey.shade600),
            filled: true,
            fillColor: _accent.withValues(alpha: 0.06),
            contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.v16, vertical: _isTouElectricity ? AppSpacing.v12 : AppSpacing.v14),
            border: fieldBorder,
            enabledBorder: fieldBorder,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              borderSide: BorderSide(color: hasError ? Colors.red.shade400 : _accent, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.v8),
        if (hasError)
          _errorLine(fieldError)
        else
          Row(
            children: [
              Icon(hasLast ? Icons.history_rounded : Icons.outlined_flag_rounded,
                  size: 14, color: Colors.grey.shade500),
              const SizedBox(width: AppSpacing.v6),
              Expanded(
                child: Text(reference,
                    style: TextStyle(
                        fontSize: AppTypography.s12, color: Colors.grey.shade600, fontFeatures: _tabular)),
              ),
            ],
          ),
      ],
    );
  }

  Widget _errorLine(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.v1),
          child: Icon(Icons.error_outline_rounded, size: 15, color: Colors.red.shade700),
        ),
        const SizedBox(width: AppSpacing.v6),
        Expanded(
          child: Text(message, style: TextStyle(color: Colors.red.shade700, fontSize: AppTypography.s12, height: 1.4)),
        ),
      ],
    );
  }

  // สรุปรอบนี้ใต้ช่องกรอก — ยังไม่มีเลขที่ใช้ได้จะแสดงคำแนะนำแทนตัวเลข 0
  Widget _resultCard({required bool hasLast}) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('สรุปรอบบิลนี้ (ถึงวันนี้)',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: AppTypography.s14, color: AppColors.textDark)),
                ),
                if (_isCalculating)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.v12),
            if (_previewValid)
              ..._resultDetails(hasLast: hasLast)
            else
              Text(
                'กรอกเลขบนมิเตอร์ แล้วระบบจะคำนวณหน่วยที่ใช้และค่า$_utilityLabelโดยประมาณให้ค่ะ',
                style: TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _resultDetails({required bool hasLast}) {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _statTile(
              label: 'ใช้ไปในรอบนี้',
              value: _previewUsedFromStart,
              pattern: '#,##0.##',
              suffix: ' $_unit',
            ),
          ),
          const SizedBox(width: AppSpacing.v10),
          Expanded(
            child: _statTile(
              label: 'ค่า$_utilityLabelโดยประมาณ',
              value: _previewCost,
              pattern: '#,##0.00',
              suffix: ' บาท',
              highlight: true,
            ),
          ),
        ],
      ),
      if (hasLast) ...[
        const SizedBox(height: AppSpacing.v10),
        Text('เพิ่มขึ้น ${_unitFormatter.format(_previewUsedFromLast)} $_unit จากครั้งก่อน',
            style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade700, fontFeatures: _tabular)),
      ],
      const SizedBox(height: AppSpacing.v4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _showCalcDetail = !_showCalcDetail),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade700,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
                fontFamily: AppTheme.fontFamily, fontSize: AppTypography.s12_5, fontWeight: FontWeight.w500),
          ),
          icon: Icon(_showCalcDetail ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
          label: Text(_showCalcDetail ? 'ซ่อนวิธีคำนวณ' : 'ดูวิธีคำนวณ'),
        ),
      ),
      if (_showCalcDetail) _calcDetail(),
    ];
  }

  // วิธีคำนวณแบบเต็ม — เลขวันนี้ลบเลขต้นรอบ (TOU แยกทีละช่วง) และอัตราที่อ้างอิง
  Widget _calcDetail() {
    final f = _unitFormatter;
    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.v2),
          child: Row(
            children: [
              Text(label, style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade700)),
              const SizedBox(width: AppSpacing.v8),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: AppTypography.s12,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.textDark,
                      fontFeatures: _tabular,
                    )),
              ),
            ],
          ),
        );
    final rows = _isTouElectricity
        ? [
            line('On-Peak (T1)',
                '${f.format(_previewPeakValue)} − ${f.format(widget.startPeak)} = '
                    '${f.format(EnergyCalculator.calculateUsed(_previewPeakValue, widget.startPeak))} $_unit'),
            line('Off-Peak (T2)',
                '${f.format(_previewOffPeakValue)} − ${f.format(widget.startOffPeak)} = '
                    '${f.format(EnergyCalculator.calculateUsed(_previewOffPeakValue, widget.startOffPeak))} $_unit'),
          ]
        : [
            line('เลขมิเตอร์วันนี้', '${f.format(_previewNormalValue)} $_unit'),
            line('ลบ เลขมิเตอร์ต้นรอบ', '${f.format(widget.startValue)} $_unit'),
          ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.v12),
      decoration: BoxDecoration(
        color: DashboardStyles.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.v6),
            child: Divider(),
          ),
          line('ใช้ไปในรอบนี้', '${f.format(_previewUsedFromStart)} $_unit', bold: true),
          const SizedBox(height: AppSpacing.v8),
          Text(
            'คิดค่า$_utilityLabelจากหน่วยที่ใช้ตั้งแต่ต้นรอบ ตามอัตราปัจจุบันของ $_providerLabel',
            style: TextStyle(fontSize: AppTypography.s11_5, height: 1.45, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // ช่องตัวเลขสรุป — highlight = พื้นสีประจำยูทิลิตี้แบบจาง (ใช้กับยอดเงิน)
  Widget _statTile({
    required String label,
    required double value,
    required String pattern,
    required String suffix,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.v12),
      decoration: BoxDecoration(
        color: highlight ? _accent.withValues(alpha: 0.1) : DashboardStyles.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppTypography.s11_5, color: highlight ? _darkAccent : Colors.grey.shade700)),
          const SizedBox(height: AppSpacing.v4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedAmount(
              value: value,
              pattern: pattern,
              suffix: suffix,
              style: TextStyle(
                fontSize: AppTypography.s20,
                fontWeight: FontWeight.w700,
                color: highlight ? _darkAccent : AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // คำแนะนำ + ปุ่มแก้ไข เมื่อเลขที่กรอกไม่ผ่านการเช็คช่วง (กล่องเตือนโทนส้ม)
  Widget _rangeIssueHelp({
    required String message,
    required IconData buttonIcon,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.v14),
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.warningBorder),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warningIcon),
              const SizedBox(width: AppSpacing.v8),
              Expanded(
                child: Text(message,
                    style: const TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: AppColors.warningText)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v10),
          OutlinedButton.icon(
            onPressed: _isSaving ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warningText,
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppColors.warningBorder),
            ),
            icon: Icon(buttonIcon, size: 18),
            label: Text(buttonLabel, style: const TextStyle(fontSize: AppTypography.s13)),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // ขั้นตอน 1 — บันทึกสำเร็จ + ประวัติของรอบนี้
  // =====================================================================
  Widget _buildSuccessStep() {
    return _scrollWithBottomButton(
      children: [
        const SizedBox(height: AppSpacing.v12),
        Center(child: _SuccessBadge(color: _accent)),
        const SizedBox(height: AppSpacing.v14),
        const Text('บันทึกสำเร็จ',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppTypography.s20, color: AppColors.textDark)),
        const SizedBox(height: AppSpacing.v2),
        Text(_shortThaiDate(_savedAt),
            textAlign: TextAlign.center, style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600)),
        const SizedBox(height: AppSpacing.v24),
        FadeSlideIn(
          delay: const Duration(milliseconds: 150),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.v16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ยอดรอบนี้ (อัปเดตแล้ว)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.s13_5, color: _accent)),
                const SizedBox(height: AppSpacing.v12),
                Row(
                  children: [
                    Expanded(
                      child: _statTile(
                        label: 'ใช้ไปในรอบนี้',
                        value: _savedUsedFromStart,
                        pattern: '#,##0.##',
                        suffix: ' $_unit',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.v10),
                    Expanded(
                      child: _statTile(
                        label: 'ค่า$_utilityLabelโดยประมาณ',
                        value: _savedCost,
                        pattern: '#,##0.00',
                        suffix: ' บาท',
                        highlight: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_historyAfterSave.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.v20),
          const Text('ประวัติการบันทึกรอบนี้', style: DashboardStyles.sectionTitle),
          const SizedBox(height: AppSpacing.v10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 250),
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.v4),
              child: Column(
                children: [
                  for (final (i, e) in _historyAfterSave.take(5).indexed) ...[
                    if (i > 0) const Divider(indent: AppSpacing.v16, endIndent: AppSpacing.v16),
                    _historyRow(e, isLatest: i == 0),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
      button: ElevatedButton(
        onPressed: () => _closeWith(true),
        style: _primaryButtonStyle,
        child: const Text('กลับหน้าหลัก'),
      ),
    );
  }

  // แถวประวัติ 1 รายการ — หน่วยที่เพิ่มจากครั้งก่อน + ค่าใช้จ่ายสะสม ณ ตอนนั้น
  Widget _historyRow(MeterHistoryEntry e, {required bool isLatest}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v16, vertical: AppSpacing.v12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isLatest ? _accent : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.v12),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.v8,
              children: [
                Text(_shortThaiDate(e.date),
                    style: const TextStyle(fontSize: AppTypography.s12_5, color: AppColors.textDark)),
                if (isLatest)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v6, vertical: AppSpacing.v1),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.v6),
                    ),
                    child: Text('ล่าสุด',
                        style: TextStyle(fontSize: AppTypography.s10, fontWeight: FontWeight.w600, color: _accent)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.v8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('+${_unitFormatter.format(e.usedFromLast)} $_unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppTypography.s13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                        fontFeatures: _tabular)),
                Text('สะสม ฿${_costFormatter.format(e.cost)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600, fontFeatures: _tabular)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// เครื่องหมายถูกในวงกลมสีประจำยูทิลิตี้ เด้งขยายเข้าจอครั้งเดียว พร้อมวงจางรอบนอก
class _SuccessBadge extends StatelessWidget {
  final Color color;

  const _SuccessBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
        ),
      ),
    );
  }
}
