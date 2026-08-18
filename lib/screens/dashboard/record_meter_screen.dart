import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/electricity_log_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/calculator.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/start_meter_fields.dart' show parseNumInput;
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
// หน้าเต็มจอสำหรับ "บันทึกมิเตอร์วันนี้" — แทนที่ช่องกรอก + ปุ่มบันทึกที่
// เดิมฝังอยู่ในการ์ดบนแดชบอร์ดโดยตรง ใช้กับทั้งไฟปกติ/TOU/น้ำ (ผ่าน
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
  final bool isTou; // มีผลเฉพาะ kind == electricity
  final String uid;
  final FirestoreService firestoreService;
  final String area; // 'bangkok' หรือ 'province' — เลือกสูตร/ผู้ให้บริการ

  final double startValue; // หน่วยต้นรอบ (ไฟปกติ/น้ำ)
  final double lastValue; // หน่วยสะสมที่บันทึกครั้งล่าสุด
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

  double _parse(TextEditingController c) => parseNumInput(c.text);

  // เรียกทุกครั้งที่พิมพ์ในช่องกรอก — ยกเลิก timer เดิม ตั้งใหม่ให้รอ
  // 500ms หลังหยุดพิมพ์ค่อยคำนวณจริง (debounce กัน Firestore read ถี่)
  void _scheduleCalc() {
    setState(() {
      _isCalculating = true;
      _previewValid = false;
      _error = '';
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _runCalc());
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
            _error = showEmptyError
                ? 'กรุณากรอกหน่วย Peak หรือ Off-Peak อย่างน้อย 1 ช่องค่ะ'
                : '';
          });
        }
        return;
      }
      final peakValue = peakEmpty ? widget.lastPeak : _parse(_peakCtrl);
      final offPeakValue = offPeakEmpty ? widget.lastOffPeak : _parse(_offPeakCtrl);

      if (peakValue < widget.startPeak || offPeakValue < widget.startOffPeak) {
        if (mounted) {
          setState(() {
            _isCalculating = false;
            _previewValid = false;
            _error = 'ค่ามิเตอร์ต้องไม่น้อยกว่าหน่วยต้นรอบค่ะ';
          });
        }
        return;
      }
      if (peakValue < widget.lastPeak || offPeakValue < widget.lastOffPeak) {
        if (mounted) {
          setState(() {
            _isCalculating = false;
            _previewValid = false;
            _error = 'ค่ามิเตอร์ต้องไม่น้อยกว่าครั้งล่าสุดค่ะ';
          });
        }
        return;
      }

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
      });
      return;
    }

    if (_valueCtrl.text.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _previewValid = false;
          _error = showEmptyError ? 'กรุณากรอกค่ามิเตอร์${_utilityLabel}ก่อนค่ะ' : '';
        });
      }
      return;
    }
    final value = _parse(_valueCtrl);
    if (value <= 0) {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _previewValid = false;
          _error = 'กรุณากรอกเป็นตัวเลขเท่านั้นค่ะ';
        });
      }
      return;
    }
    if (value < widget.startValue) {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _previewValid = false;
          _error =
              'ต้องไม่น้อยกว่าหน่วยต้นรอบ (${NumberFormat('#,##0.##').format(widget.startValue)}) ค่ะ';
        });
      }
      return;
    }
    if (value < widget.lastValue) {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _previewValid = false;
          _error =
              'ต้องไม่น้อยกว่าครั้งล่าสุด (${NumberFormat('#,##0.##').format(widget.lastValue)}) ค่ะ';
        });
      }
      return;
    }

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
    });
  }

  // กดปุ่ม "ยืนยันบันทึก" — ยกเลิก debounce ที่ค้างอยู่แล้วบังคับคำนวณ
  // ทันที (เผื่อผู้ใช้พิมพ์เสร็จแล้วรีบกดก่อนครบ 500ms) จากนั้นค่อยบันทึก
  // จริงถ้าค่าที่ได้ถูกต้อง
  Future<void> _onConfirmTap() async {
    _debounce?.cancel();
    setState(() => _isCalculating = true);
    await _runCalc(showEmptyError: true);
    if (!_previewValid) return;
    await _doSave();
  }

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
        setState(() => _error = 'เกิดข้อผิดพลาดบางอย่างค่ะ กรุณาลองใหม่อีกครั้ง');
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
          backgroundColor: DashboardStyles.background,
          elevation: 0,
          foregroundColor: DashboardStyles.textDark,
          automaticallyImplyLeading: false,
          leadingWidth: 56,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Center(
              child: InkWell(
                onTap: () => _closeWith(false),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: DashboardStyles.background,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back, size: 19),
                ),
              ),
            ),
          ),
          title: _step == 0
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('ขั้นตอนที่ 1 จาก 2',
                        style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.normal)),
                    Text('บันทึกมิเตอร์$_utilityLabel',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                )
              : const Text('บันทึกสำเร็จ'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _accent, width: 1.6),
          ),
        );

    Widget lastValueChips(double last, double start) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: DashboardStyles.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ค่าล่าสุด', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Text('${formatter.format(last)} $_unit',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: DashboardStyles.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ต้นรอบ', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Text('${formatter.format(start)} $_unit',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
    }) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: _accent),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: _accent)),
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
            const SizedBox(height: 8),
            lastValueChips(last, start),
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
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300, width: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calculate_outlined, size: 15, color: _accent),
                        const SizedBox(width: 6),
                        const Text('การคำนวณ',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_isTouElectricity) ...[
                      _calcRow('รวมมิเตอร์วันนี้ (Peak+Off-Peak)',
                          '${formatter.format(_previewPeakValue + _previewOffPeakValue)} $_unit'),
                      const SizedBox(height: 6),
                      _calcRow('รวมต้นรอบบิล',
                          '− ${formatter.format(widget.startPeak + widget.startOffPeak)} $_unit'),
                    ] else ...[
                      _calcRow('มิเตอร์วันนี้', '${formatter.format(_previewNormalValue)} $_unit'),
                      const SizedBox(height: 6),
                      _calcRow('ต้นรอบบิล', '− ${formatter.format(widget.startValue)} $_unit'),
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
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAEEDA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'ค่า$_utilityLabelโดยประมาณ (ถึงวันนี้)\nอ้างอิงอัตราปัจจุบันของ $_providerLabel',
                        style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF854F0B)),
                      ),
                    ),
                    Text('฿${costFormatter.format(_previewCost)}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF412402))),
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
            ),
            const SizedBox(height: 10),
            fieldCard(
              icon: Icons.nightlight_outlined,
              label: 'Off-Peak (T2)',
              controller: _offPeakCtrl,
              last: widget.lastOffPeak,
              start: widget.startOffPeak,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('เว้นช่องไหนไว้ได้ ถ้าช่วงนั้นยังไม่ได้ใช้เพิ่ม',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
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
              fontSize: 26,
            ),
          ],
          const SizedBox(height: 14),
          if (_isCalculating)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
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
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                ],
              ),
            ),
          calculationPanel(),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
            ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _onConfirmTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _calcRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        Text(value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
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
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 12),
                const Text('บันทึกสำเร็จ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text(_shortThaiDate(_savedAt), style: DashboardStyles.lastValueStyle),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: DashboardStyles.whiteCard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ใช้ไปในรอบนี้ (อัปเดตแล้ว)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: _accent)),
                const SizedBox(height: 10),
                _calcRow('ใช้ไปในรอบนี้', '${formatter.format(_savedUsedFromStart)} $_unit', bold: true),
                const SizedBox(height: 4),
                _calcRow('ค่า$_utilityLabelโดยประมาณ', '฿${costFormatter.format(_savedCost)}', bold: true),
              ],
            ),
          ),
          if (_historyAfterSave.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('ประวัติการบันทึกรอบนี้', style: DashboardStyles.sectionTitle),
            const SizedBox(height: 8),
            ..._historyAfterSave.take(5).map((e) {
              final isLatest = e == _historyAfterSave.first;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: DashboardStyles.whiteCard(radius: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(_shortThaiDate(e.date), style: const TextStyle(fontSize: 12.5)),
                        if (isLatest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('ล่าสุด', style: TextStyle(fontSize: 10, color: _accent)),
                          ),
                        ],
                      ],
                    ),
                    Text('+${formatter.format(e.usedFromLast)} $_unit • ฿${costFormatter.format(e.cost)}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
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
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('กลับหน้าหลัก'),
            ),
          ),
        ],
      ),
    );
  }
}