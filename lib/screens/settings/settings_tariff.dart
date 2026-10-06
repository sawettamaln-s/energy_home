part of 'settings_screen.dart';

// ==================== ประเภทอัตราค่าไฟ (มิเตอร์ปกติ) ====================
// เปิดได้ทั้งจากหน้าตั้งค่า และจาก popup แนะนำบนหน้าหลัก (ดู
// showTariffHintPopup) — ค่าเริ่มต้นคือประเภทใช้เกิน 150 หน่วยของบ้านส่วนใหญ่
// รหัสประเภทแสดงตามการไฟฟ้าของพื้นที่ผู้ใช้ (ดู EnergyCalculator.tariffCode)

String tariffLabel(String tariff, String area) =>
    'ประเภท ${EnergyCalculator.tariffCode(tariff, area)}';

// อธิบายวิธีดูประเภทอัตราจากใบแจ้งหนี้และกติกาการจัดประเภทของการไฟฟ้า
void showTariffHowToInfo(BuildContext context, String area) {
  final small = EnergyCalculator.tariffCode(EnergyCalculator.tariffSmall, area);
  final standard =
      EnergyCalculator.tariffCode(EnergyCalculator.tariffStandard, area);
  final utility = area == 'bangkok' ? 'การไฟฟ้านครหลวง' : 'การไฟฟ้าส่วนภูมิภาค';
  showInfoDialog(
    context,
    title: 'ดูประเภทอัตราค่าไฟยังไง?',
    message: 'บนใบแจ้งหนี้ค่าไฟจะระบุประเภทอัตราที่ใช้คิดเงินไว้ บ้านอยู่อาศัยของ'
        '$utilityมี 2 ประเภท ($small หรือ $standard) ให้เลือกในแอปตามนั้นค่ะ\n\n'
        'การไฟฟ้าจัดประเภทจากขนาดมิเตอร์และการใช้ย้อนหลัง:\n'
        '• มิเตอร์ใหญ่กว่า 5 แอมแปร์ (บ้านส่วนใหญ่) เป็นประเภท $standard เสมอ\n'
        '• มิเตอร์ไม่เกิน 5 แอมแปร์ ถ้าใช้เกิน 150 หน่วยติดต่อกัน 3 เดือน เดือน'
        'ถัดไปเป็นประเภท $standard และถ้าใช้ไม่เกิน 150 หน่วยติดต่อกัน 3 เดือน '
        'จะกลับเป็นประเภท $small (อัตราถูกกว่า)\n\n'
        'อัตราค่าไฟเท่ากันทั้งกรุงเทพฯ/ปริมณฑลและต่างจังหวัด ต่างกันแค่รหัสประเภท '
        'ส่วนมิเตอร์ TOU มีอัตราของตัวเอง ไม่ต้องตั้งค่านี้',
  );
}

// เลือกประเภทอัตราค่าไฟตามที่พิมพ์บนใบแจ้งหนี้ — บันทึกแล้วคิดเงินของรอบ
// ปัจจุบันใหม่ทั้งรอบ บิลเดือนก่อนๆ ไม่เปลี่ยน (ดู setElectricityTariff)
// [initial] = ตัวเลือกที่เลือกไว้ให้ตอนเปิด (ไม่ส่ง = ประเภทปัจจุบันของผู้ใช้)
Future<void> showElectricityTariffDialog(
  BuildContext context, {
  required UserModel user,
  required FirestoreService firestoreService,
  String? initial,
  VoidCallback? onSaved,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _TariffSheet(
      user: user,
      firestoreService: firestoreService,
      initial: initial ?? user.electricityTariff,
      onSaved: onSaved,
    ),
  );
}

class _TariffSheet extends StatefulWidget {
  final UserModel user;
  final FirestoreService firestoreService;
  final String initial;
  final VoidCallback? onSaved;

  const _TariffSheet({required this.user, required this.firestoreService, required this.initial, this.onSaved});

  @override
  State<_TariffSheet> createState() => _TariffSheetState();
}

class _TariffSheetState extends State<_TariffSheet> {
  late String _selected = widget.initial;
  bool _isSaving = false;
  String? _error;

  bool get _changed => _selected != widget.user.electricityTariff;

  Future<void> _save() async {
    if (!_changed) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.firestoreService.setElectricityTariff(widget.user, _selected);
      widget.onSaved?.call();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'บันทึกไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _option({
    required String tariff,
    required String title,
    required String detail,
    required String serviceFee,
  }) {
    final selected = _selected == tariff;
    final inUse = widget.user.electricityTariff == tariff;
    final code = EnergyCalculator.tariffCode(tariff, widget.user.area);
    return Material(
      color: selected ? AppColors.primaryGreen.withValues(alpha: 0.06) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: selected ? AppColors.primaryGreen : Colors.grey.shade300, width: selected ? 1.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() {
          _selected = tariff;
          _error = null;
        }),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.v14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20, color: selected ? AppColors.primaryGreen : Colors.grey.shade500),
              const SizedBox(width: AppSpacing.v10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.v6,
                      runSpacing: AppSpacing.v4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('ประเภท $code',
                            style: const TextStyle(
                                fontSize: AppTypography.s15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        if (inUse)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v6, vertical: AppSpacing.v2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                            ),
                            child: Text('ใช้อยู่',
                                style: TextStyle(
                                    fontSize: AppTypography.s11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700)),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.v2),
                    Text(title,
                        style: const TextStyle(
                            fontSize: AppTypography.s13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    const SizedBox(height: AppSpacing.v2),
                    Text(detail,
                        style: TextStyle(fontSize: AppTypography.s12, height: 1.4, color: Colors.grey.shade600)),
                    const SizedBox(height: AppSpacing.v6),
                    Text('ค่าบริการ $serviceFee บาท/เดือน',
                        style: TextStyle(
                            fontSize: AppTypography.s12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.user.area;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v10, AppSpacing.v16, AppSpacing.v16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetGrabber(),
                const SizedBox(height: AppSpacing.v6),
                Row(
                  children: [
                    const Expanded(
                      child: Text('ประเภทอัตราค่าไฟ',
                          style: TextStyle(
                              fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    ),
                    IconButton(
                      tooltip: 'ดูประเภทอัตราค่าไฟยังไง',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.info_outline, size: 20, color: Colors.grey.shade600),
                      onPressed: () => showTariffHowToInfo(context, area),
                    ),
                  ],
                ),
                Text('เลือกให้ตรงกับประเภทที่พิมพ์บนใบแจ้งหนี้ค่าไฟใบล่าสุดค่ะ',
                    style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600)),
                const SizedBox(height: AppSpacing.v14),
                _option(
                  tariff: EnergyCalculator.tariffStandard,
                  title: 'ใช้เกิน 150 หน่วย/เดือน',
                  detail: 'บ้านส่วนใหญ่ (มิเตอร์ใหญ่กว่า 5 แอมแปร์) ถ้าไม่แน่ใจให้เลือกประเภทนี้',
                  serviceFee: TariffTables.electricityStandardServiceFee.toStringAsFixed(2),
                ),
                const SizedBox(height: AppSpacing.v8),
                _option(
                  tariff: EnergyCalculator.tariffSmall,
                  title: 'ใช้ไม่เกิน 150 หน่วย/เดือน',
                  detail: 'มิเตอร์ไม่เกิน 5 แอมแปร์ ที่ใช้ไม่เกิน 150 หน่วยติดต่อกัน 3 เดือน อัตราถูกกว่า',
                  serviceFee: TariffTables.electricitySmallServiceFee.toStringAsFixed(2),
                ),
                const SizedBox(height: AppSpacing.v12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.autorenew_rounded, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: AppSpacing.v6),
                    Expanded(
                      child: Text(
                        'เมื่อเปลี่ยน ระบบจะคำนวณค่าไฟของรอบปัจจุบันใหม่ตามประเภทที่เลือก บิลเดือนก่อนๆ ไม่เปลี่ยนค่ะ',
                        style: TextStyle(fontSize: AppTypography.s12, height: 1.4, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.v12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: AppSpacing.v6),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.red.shade700)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v16, AppSpacing.v16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: SafeArea(
            top: false,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_changed ? 'บันทึก' : 'ปิด'),
            ),
          ),
        ),
      ],
    );
  }
}

// popup บนหน้าหลักเมื่อบิล 3 เดือนติดกันเข้าเงื่อนไขเปลี่ยนประเภท (ดู
// TariffAdvisor) — แค่แนะนำ ผู้ใช้เลือก "ไว้ทีหลัง" ได้ ไม่บังคับเปลี่ยน
Future<void> showTariffHintPopup(
  BuildContext context, {
  required TariffHint hint,
  required UserModel user,
  required FirestoreService firestoreService,
}) async {
  final first = hint.bills.first;
  final latest = hint.latest;
  final range = '${thaiMonths[first.month - 1]} - '
      '${thaiMonths[latest.month - 1]} ${latest.year + 543}';
  final toSmall = hint.suggestedTariff == EnergyCalculator.tariffSmall;
  final suggested = tariffLabel(hint.suggestedTariff, user.area);
  final goAdjust = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.v20)),
      title: Row(
        children: [
          const Expanded(
            child: Text('ลองตรวจประเภทอัตราค่าไฟ',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: AppTypography.s17)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.info_outline,
                color: DashboardStyles.primaryGreen, size: 20),
            onPressed: () => showTariffHowToInfo(context, user.area),
          ),
        ],
      ),
      content: Text(
        toSmall
            ? 'บ้านคุณใช้ไฟไม่เกิน 150 หน่วยติดต่อกัน 3 เดือน ($range) ถ้ามิเตอร์'
                'ขนาดไม่เกิน 5 แอมแปร์ บิลถัดไปอาจเปลี่ยนเป็น$suggested ซึ่ง'
                'ถูกกว่า\n\nตรวจประเภทบนใบแจ้งหนี้ใบถัดไป ถ้าเปลี่ยนจริง'
                'ปรับในแอปให้ตรงได้เลยค่ะ'
            : 'บ้านคุณใช้ไฟเกิน 150 หน่วยติดต่อกัน 3 เดือน ($range) บิลถัดไป'
                'มักเปลี่ยนกลับเป็น$suggested\n\nตรวจประเภทบนใบแจ้งหนี้ใบถัดไป '
                'ถ้าเปลี่ยนจริงปรับในแอปให้ตรงได้เลยค่ะ',
        style: const TextStyle(fontSize: AppTypography.s13_5, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('ไว้ทีหลัง'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: DashboardStyles.primaryGreen,
            foregroundColor: Colors.white,
          ),
          child: const Text('ปรับประเภทอัตรา'),
        ),
      ],
    ),
  );
  if (goAdjust == true && context.mounted) {
    await showElectricityTariffDialog(
      context,
      user: user,
      firestoreService: firestoreService,
      initial: hint.suggestedTariff,
    );
  }
}
