part of 'settings_screen.dart';

// ==================== ประเภทอัตราค่าไฟ (มิเตอร์ปกติ) ====================
// เปิดได้ทั้งจากหน้าตั้งค่า และจาก popup แนะนำบนหน้าหลัก (ดู
// showTariffHintPopup) — ค่าเริ่มต้นคือประเภท 1.2 / 1.1.2 ของบ้านส่วนใหญ่

String tariffLabel(String tariff) => tariff == EnergyCalculator.tariffSmall
    ? 'ประเภท 1.1.1'
    : 'ประเภท 1.1.2 / 1.2';

// อธิบายวิธีดูประเภทอัตราจากใบแจ้งหนี้และกติกาการจัดประเภทของการไฟฟ้า
void showTariffHowToInfo(BuildContext context) {
  showInfoDialog(
    context,
    title: 'ดูประเภทอัตราค่าไฟยังไง?',
    message: 'บนใบแจ้งหนี้ค่าไฟจะระบุประเภทอัตราที่ใช้คิดเงินไว้ เช่น 1.1.1, '
        '1.1.2 หรือ 1.2 ให้เลือกในแอปตามนั้นค่ะ\n\n'
        'การไฟฟ้าจัดประเภทจากขนาดมิเตอร์และการใช้ย้อนหลัง:\n'
        '• มิเตอร์ใหญ่กว่า 5 แอมแปร์ (บ้านส่วนใหญ่) เป็นประเภท 1.2 / 1.1.2 เสมอ\n'
        '• มิเตอร์ไม่เกิน 5 แอมแปร์ ถ้าใช้ไม่เกิน 150 หน่วย/เดือนติดต่อกัน 3 เดือน '
        'บิลเดือนถัดไปเป็นประเภท 1.1.1 (อัตราถูกกว่า) และถ้าใช้เกิน 150 หน่วย '
        'ติดต่อกัน 3 เดือน จะกลับเป็น 1.1.2\n\n'
        'ใช้กติกาเดียวกันทั้งกรุงเทพฯ/ปริมณฑล (กฟน.) และต่างจังหวัด (กฟภ.) '
        'อัตราเท่ากันทั้งประเทศ ส่วนมิเตอร์ TOU มีอัตราของตัวเอง ไม่ต้องตั้งค่านี้',
  );
}

// ตัวเลือกประเภทอัตรา 1 ช่องในหน้าต่างเลือก — กรอบเขียวเมื่อเลือกอยู่
Widget _tariffOption({
  required String title,
  required String detail,
  required bool selected,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppSpacing.v12),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v12),
      decoration: BoxDecoration(
        color: selected ? AppColors.softGreenBg : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v12),
        border: Border.all(
          color: selected ? DashboardStyles.primaryGreen : Colors.grey.shade300,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: selected ? DashboardStyles.primaryGreen : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTypography.s14)),
                const SizedBox(height: 2),
                Text(detail,
                    style: TextStyle(
                        fontSize: AppTypography.s12,
                        color: Colors.grey.shade700,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    ),
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
  String selected = initial ?? user.electricityTariff;
  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.v20)),
        title: Row(
          children: [
            const Expanded(
              child: Text('ประเภทอัตราค่าไฟ',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTypography.s17)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.info_outline,
                  color: DashboardStyles.primaryGreen, size: 20),
              onPressed: () => showTariffHowToInfo(context),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'เลือกให้ตรงกับประเภทที่พิมพ์บนใบแจ้งหนี้ค่าไฟใบล่าสุดค่ะ',
                style: TextStyle(
                    fontSize: AppTypography.s12_5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              _tariffOption(
                title: 'ประเภท 1.1.2 / 1.2 (ค่าเริ่มต้น)',
                detail: 'บ้านส่วนใหญ่ (มิเตอร์ใหญ่กว่า 5 แอมแปร์ หรือใช้เกิน '
                    '150 หน่วย/เดือน)',
                selected: selected == EnergyCalculator.tariffStandard,
                onTap: () => setDialogState(
                    () => selected = EnergyCalculator.tariffStandard),
              ),
              const SizedBox(height: 8),
              _tariffOption(
                title: 'ประเภท 1.1.1',
                detail: 'มิเตอร์ไม่เกิน 5 แอมแปร์ ที่ใช้ไม่เกิน 150 หน่วย/เดือน '
                    'ติดต่อกัน 3 เดือน (อัตราถูกกว่า)',
                selected: selected == EnergyCalculator.tariffSmall,
                onTap: () => setDialogState(
                    () => selected = EnergyCalculator.tariffSmall),
              ),
              const SizedBox(height: 12),
              Text(
                'เมื่อเปลี่ยน ระบบจะคำนวณค่าไฟของรอบปัจจุบันใหม่ตามประเภทที่เลือก '
                'บิลเดือนก่อนๆ ไม่เปลี่ยนค่ะ',
                style: TextStyle(
                    fontSize: AppTypography.s12,
                    color: Colors.grey.shade600,
                    height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selected != user.electricityTariff) {
                await firestoreService.setElectricityTariff(user, selected);
                onSaved?.call();
              }
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DashboardStyles.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );
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
            onPressed: () => showTariffHowToInfo(context),
          ),
        ],
      ),
      content: Text(
        toSmall
            ? 'บ้านคุณใช้ไฟไม่เกิน 150 หน่วยติดต่อกัน 3 เดือน ($range) ถ้ามิเตอร์'
                'ขนาดไม่เกิน 5 แอมแปร์ บิลถัดไปอาจเปลี่ยนเป็นประเภท 1.1.1 ซึ่ง'
                'ถูกกว่า\n\nตรวจประเภทบนใบแจ้งหนี้ใบถัดไป ถ้าเปลี่ยนจริง'
                'ปรับในแอปให้ตรงได้เลยค่ะ'
            : 'บ้านคุณใช้ไฟเกิน 150 หน่วยติดต่อกัน 3 เดือน ($range) บิลถัดไป'
                'มักเปลี่ยนกลับเป็นประเภท 1.1.2\n\nตรวจประเภทบนใบแจ้งหนี้ใบถัดไป '
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
