import 'package:flutter/material.dart';

/// Dialog แบบ "ไอคอน info + หัวข้อ + ข้อความ + ปุ่มเข้าใจแล้ว" ที่ใช้ซ้ำ
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
  String buttonLabel = 'เข้าใจแล้ว',
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

/// Popup อธิบายที่มาของตัวเลขประมาณการค่าไฟอุปกรณ์ — ใช้ร่วมกันระหว่าง
/// appliance_screen.dart และ analysis_screen.dart (เดิมมีโค้ดซ้ำกันทั้งสองที่)
void showApplianceEstimateInfoDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text('ตัวเลขนี้คำนวณอย่างไร?', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ใช้สูตรมาตรฐานเดียวกับที่การไฟฟ้าและเว็บคำนวณค่าไฟทั่วไปใช้\n\n'
              'หน่วยไฟ/วัน = (วัตต์ × ชั่วโมงที่เปิด ÷ 1,000)\n'
              'ค่าไฟ = หน่วยไฟ × อัตราเฉลี่ยประมาณการ 4.5 บาท/หน่วย\n\n'
              'อัตรานี้เป็นค่าเฉลี่ยโดยประมาณ (รวม Ft และ VAT) ไม่ใช่อัตราขั้นบันไดจริง '
              'จึงอาจไม่ตรงกับยอดบิลทุกประการ แต่ใช้เทียบสัดส่วนระหว่างอุปกรณ์ได้',
              style: TextStyle(fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'อุปกรณ์ที่มีคอมเพรสเซอร์ เช่น ตู้เย็นหรือแอร์ วัตต์ที่ระบุบนฉลาก '
                      'มักเป็นกำลังไฟสูงสุดขณะคอมเพรสเซอร์ทำงาน ไม่ใช่ค่าเฉลี่ยที่ใช้จริงตลอดเวลา '
                      '(คอมเพรสเซอร์ตัดเข้า-ออกเป็นรอบ ไม่ทำงานเต็มกำลังตลอด 24 ชั่วโมง) '
                      'การกรอกวัตต์บนฉลากตรงๆ อาจได้ตัวเลขสูงกว่าความเป็นจริง '
                      'สำหรับค่าที่แม่นยำกว่านี้ ให้ดู "หน่วยไฟฟ้าต่อปี" บนฉลากประหยัดไฟเบอร์ 5 '
                      'ของอุปกรณ์นั้นแทน',
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: Colors.orange.shade900),
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