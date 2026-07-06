import 'package:flutter/material.dart';

/// Dialog แบบ "ไอคอน info + หัวข้อ + ข้อความ + ปุ่มเข้าใจแล้วค่ะ" ที่ใช้ซ้ำ
/// ทั่วแอป (เดิมก็อปวางโครงเดิมซ้ำอยู่ ~14 ที่ กระจายอยู่ใน setup_screen.dart,
/// settings_screen.dart (9 จุด), dashboard_screen.dart, appliance_screen.dart,
/// analysis_screen.dart) — คู่กับ showConfirmDialog ใน confirm_dialog.dart
///
/// ใช้ได้ 2 แบบ:
/// 1) ข้อความล้วน: ส่ง `message` (แบบเดิมส่วนใหญ่ในแอป)
/// 2) เนื้อหากำหนดเอง (เช่น มี Container สีพิเศษแทรกอยู่): ส่ง `contentBuilder`
///    แทน `message` (ใช้กรณีอย่าง _showEstimateInfoPopup ที่มีกล่องเตือน
///    เพิ่มเติมนอกเหนือจากข้อความปกติ)
void showInfoDialog(
  BuildContext context, {
  required String title,
  String? message,
  WidgetBuilder? contentBuilder,
  Color iconColor = const Color(0xFF2E7D32),
  String buttonLabel = 'เข้าใจแล้วค่ะ',
}) {
  assert(message != null || contentBuilder != null,
      'ต้องส่ง message หรือ contentBuilder อย่างใดอย่างหนึ่ง');

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.info_outline, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
        ],
      ),
      content: SingleChildScrollView(
        child: contentBuilder != null
            ? contentBuilder(context)
            : Text(
                message!,
                style: const TextStyle(fontSize: 13.5, height: 1.5),
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