import 'package:flutter/material.dart';

import '../screens/dashboard/dashboard_styles.dart';
import '../utils/appliance_rate.dart';
import '../utils/thai_date_utils.dart';

/// Dialog แบบ "ไอคอน info + หัวข้อ + ข้อความ + ปุ่มเข้าใจแล้ว" ที่ใช้ซ้ำ
/// ทั่วแอป — คู่กับ showConfirmDialog ใน confirm_dialog.dart
///
/// ใช้ได้ 2 แบบ:
/// 1) ข้อความล้วน: ส่ง `message` (แบบที่ใช้ส่วนใหญ่ในแอป)
/// 2) เนื้อหากำหนดเอง (เช่น มี Container สีพิเศษแทรกอยู่): ส่ง `contentBuilder`
///    แทน `message` (เช่น showApplianceEstimateInfoDialog ด้านล่าง ที่มีกล่อง
///    เตือนเพิ่มเติมนอกเหนือจากข้อความปกติ)
void showInfoDialog(
  BuildContext context, {
  required String title,
  String? message,
  WidgetBuilder? contentBuilder,
  Color iconColor = DashboardStyles.primaryGreen,
  String buttonLabel = 'เข้าใจแล้ว',
}) {
  assert(message != null || contentBuilder != null,
      'ต้องส่ง message หรือ contentBuilder อย่างใดอย่างหนึ่ง');

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v16)),
      title: Row(
        children: [
          Icon(Icons.info_outline, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: AppTypography.s16))),
        ],
      ),
      content: SingleChildScrollView(
        child: contentBuilder != null
            ? contentBuilder(context)
            : Text(
                message!,
                style: const TextStyle(fontSize: AppTypography.s13_5, height: 1.5),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(buttonLabel),
        ),
      ],
    ),
  );
}

/// Popup อธิบายที่มาของตัวเลขประมาณการค่าไฟอุปกรณ์ — ใช้ร่วมกันระหว่าง
/// หน้าอุปกรณ์และฟอร์มเพิ่ม/แก้ไขอุปกรณ์ — [rate] คืออัตราที่
/// หน้านั้นใช้คำนวณจริง (จากบิลล่าสุดของผู้ใช้ หรือค่าเฉลี่ยประมาณการ)
void showApplianceEstimateInfoDialog(
  BuildContext context, {
  ApplianceRate rate = ApplianceRate.fallback,
}) {
  final bill = rate.sourceBill;
  final rateText = rate.perUnit.toStringAsFixed(2);
  final rateExplanation = bill != null
      ? 'อัตรานี้คิดจากบิลค่าไฟล่าสุดของคุณ (${thaiMonths[bill.month - 1]} '
          '${bill.year + 543}: ค่าไฟ ${bill.electricityCost.toStringAsFixed(2)} บาท '
          '÷ ${bill.electricityUsed.toStringAsFixed(0)} หน่วย) ซึ่งรวมอัตราขั้นบันได '
          'ค่า Ft ค่าบริการ และ VAT ตามการใช้จริงของบ้านคุณแล้ว ใช้เทียบสัดส่วน'
          'ระหว่างอุปกรณ์ได้ แต่ยอดรวมอาจไม่ตรงกับบิลทุกประการ'
      : 'ยังไม่มีบิลที่มีทั้งค่าไฟและหน่วยที่ใช้ จึงใช้ค่าเฉลี่ยประมาณการ '
          '(รวม Ft และ VAT) ไปก่อน เมื่อมีบิลแล้วระบบจะเปลี่ยนไปใช้อัตราเฉลี่ย'
          'จากบิลล่าสุดของคุณเอง';
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v16)),
      title: const Row(
        children: [
          Icon(Icons.info_outline, color: DashboardStyles.primaryGreen, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text('ตัวเลขนี้คำนวณอย่างไร?', style: TextStyle(fontSize: AppTypography.s16)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ใช้สูตรมาตรฐานเดียวกับที่การไฟฟ้าและเว็บคำนวณค่าไฟทั่วไปใช้\n\n'
              'หน่วยไฟ/วัน = วัตต์ × ชั่วโมงที่เปิด ÷ 1,000 × สัดส่วนเวลาที่ทำงานจริง\n'
              'ค่าไฟ = หน่วยไฟ × อัตราเฉลี่ย $rateText บาท/หน่วย\n\n'
              '$rateExplanation',
              style: const TextStyle(fontSize: AppTypography.s13_5, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(AppSpacing.v10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.v10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.warningIcon),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ตู้เย็นและแอร์ที่เลือกจากรายการ วัตต์บนฉลากคือกำลังไฟขณะคอมเพรสเซอร์ทำงาน '
                      'ซึ่งตัดเข้า-ออกเป็นรอบ ระบบจึงคิดเฉพาะช่วงที่ทำงานโดยประมาณ '
                      '(ตู้เย็น 35% แอร์ 60% ของเวลาที่เปิด) อุปกรณ์อื่นคิดเต็มทุกชั่วโมง '
                      'ตัวเลขทั้งหมดเป็นค่าประมาณ ถ้าต้องการแม่นยำกว่านี้ ให้ดู '
                      '"หน่วยไฟฟ้าต่อปี" บนฉลากประหยัดไฟเบอร์ 5 ของอุปกรณ์นั้น',
                      style: TextStyle(
                          fontSize: AppTypography.s12_5,
                          height: 1.5,
                          color: AppColors.warningText),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('เข้าใจแล้ว'),
        ),
      ],
    ),
  );
}