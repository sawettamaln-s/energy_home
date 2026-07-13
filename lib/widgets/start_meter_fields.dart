import 'package:flutter/material.dart';

import 'info_dialog.dart';

/// ชุดฟิลด์ "เลขมิเตอร์สะสม" ที่ใช้ร่วมกันทั้ง 3 จุดในแอป:
/// - หน้าตั้งค่า > บันทึกมิเตอร์ต้นรอบ (settings_start_meter.dart)
/// - ฟอร์มบันทึกบิลย้อนหลัง เดือนล่าสุด (settings_bill_history.dart)
/// - ขั้นตอนตั้งค่าเริ่มต้นตอนสมัคร (setup_screen.dart)
///
/// เดิมทั้ง 3 จุดนี้ก็อปโค้ด UI + ข้อความชุดนี้แยกกันเอง ทำให้เกิดบั๊กจาก
/// ความไม่ตรงกัน (เช่น billingMonth เก็บคนละความหมาย) ไปแล้วครั้งหนึ่ง — ย้าย
/// มาเป็น widget เดียวใช้ร่วมกัน แก้ตรงไหนก็แก้จุดเดียวจบทั้ง 3 ที่
///
/// เรื่องคำที่ใช้: ตั้งใจเลือกคำว่า "เลขมิเตอร์สะสม" (ไม่ใช้คำว่า "หน่วยไฟฟ้า"
/// หรือ "หน่วยที่ใช้" เด็ดขาด) เพื่อไม่ให้ปนกับฟิลด์ "หน่วยที่ใช้เดือนนี้" ใน
/// ฟอร์มบันทึกบิลย้อนหลัง ซึ่งเป็นคนละความหมายกันโดยสิ้นเชิง (เลขสะสมบน
/// มิเตอร์ vs จำนวนหน่วยที่ใช้ไปในเดือนนั้น) — ใส่ตัวอย่างตัวเลขกำกับไว้ใน
/// hint ทุกช่องด้วย เพื่อให้เห็น "ขนาด" ของตัวเลขที่ควรกรอกโดยไม่ต้องเปิด
/// popup อธิบายก่อนถึงจะรู้
///
/// เรื่องสี: ตอนแรกใช้กรอบสีฟ้า แต่พอดูจริงแล้วแอปทั้งหมดใช้เขียว
/// (0xFF2E7D32) เป็นสีหลักอย่างเดียว กรอบฟ้าเลยดูเหมือนหลุดมาจากแอปอื่น
/// เปลี่ยนเป็นกรอบเทาเป็นกลางแทน ไม่แข่งกับสีหลักของแอป
class StartMeterFieldsSection extends StatelessWidget {
  final bool isTou;
  final TextEditingController electricityCtrl;
  final TextEditingController peakCtrl;
  final TextEditingController offPeakCtrl;
  final TextEditingController waterCtrl;

  /// หัวข้อ section — ปรับได้ตามบริบทที่ใช้ (แต่ละ 3 จุดมีบริบทต่างกัน
  /// เล็กน้อย เช่น "เลขมิเตอร์สะสมต้นรอบ" ในหน้าตั้งค่า vs "ตั้งเลขมิเตอร์
  /// ต้นรอบเดือนถัดไปเลยไหม?" ในฟอร์มบิลย้อนหลัง)
  final String title;

  /// คำอธิบายสั้นใต้หัวข้อ — ปรับได้ตามบริบท (เช่น "ไม่บังคับ" หรือไม่)
  final String subtitle;

  const StartMeterFieldsSection({
    super.key,
    required this.isTou,
    required this.electricityCtrl,
    required this.peakCtrl,
    required this.offPeakCtrl,
    required this.waterCtrl,
    required this.title,
    required this.subtitle,
  });

  void _showWhatIsThisPopup(BuildContext context) {
    showInfoDialog(
      context,
      title: 'เลขมิเตอร์สะสมคืออะไร?',
      contentBuilder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'เปิดใบแจ้งหนี้ค่าไฟ/ค่าน้ำ แล้วมองหาช่อง "เลขอ่านครั้งหลัง" '
            'หรือ "Last Meter Reading" — คือตัวเลขที่มิเตอร์อ่านได้ล่าสุด '
            'ตอนเจ้าหน้าที่มาจดในรอบบิลนั้น (ไม่ใช่ "เลขอ่านครั้งก่อน" '
            'ที่อยู่คู่กัน เพราะเป็นเลขของรอบก่อนหน้า)',
            style: TextStyle(fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.straighten,
                    size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'เป็นเลขสะสมบนหน้าปัดมิเตอร์ตั้งแต่วันที่ติดตั้ง '
                    'ไม่ใช่ "หน่วยที่ใช้เดือนนี้" ที่กรอกในฟอร์มบันทึกบิล '
                    '— ถ้าเพิ่งเปลี่ยนมิเตอร์ใหม่หรือเพิ่งขอมิเตอร์ครั้งแรก '
                    'เลขนี้อาจเริ่มจากตัวเลขน้อยๆ ได้ตามปกติ ไม่ต้องกังวล',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required String suffixText,
    required IconData icon,
    required Color iconColor,
  }) {
    return InputDecoration(
      hintText: hint,
      suffixText: suffixText,
      prefixIcon: Icon(icon, color: iconColor, size: 20),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String suffixText,
    required IconData icon,
    required Color iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _decoration(
              hint: hint, suffixText: suffixText, icon: icon, iconColor: iconColor),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed, size: 17, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.info_outline,
                    size: 18, color: Colors.grey.shade600),
                onPressed: () => _showWhatIsThisPopup(context),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),

          // TOU: On-Peak / Off-Peak แยกสองช่อง — ใช้ LayoutBuilder เพื่อ
          // สลับเป็นเรียงต่อกันแนวตั้งอัตโนมัติเวลาจอแคบ (เช่นมือถือจอเล็ก
          // ที่แบ่งครึ่งแนวนอนแล้วช่องจะแคบเกินไปจนตัวเลขและ suffix ชนกัน)
          if (isTou)
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 340;
                final peakField = _field(
                  controller: peakCtrl,
                  label: 'เลขมิเตอร์ On-Peak',
                  hint: 'เช่น 8,500',
                  suffixText: 'หน่วย',
                  icon: Icons.bolt,
                  iconColor: Colors.orange.shade700,
                );
                final offPeakField = _field(
                  controller: offPeakCtrl,
                  label: 'เลขมิเตอร์ Off-Peak',
                  hint: 'เช่น 5,500',
                  suffixText: 'หน่วย',
                  icon: Icons.bolt_outlined,
                  iconColor: Colors.blueGrey,
                );
                if (narrow) {
                  return Column(
                    children: [
                      peakField,
                      const SizedBox(height: 12),
                      offPeakField,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: peakField),
                    const SizedBox(width: 10),
                    Expanded(child: offPeakField),
                  ],
                );
              },
            )
          else
            _field(
              controller: electricityCtrl,
              label: 'เลขมิเตอร์ไฟฟ้า',
              hint: 'เช่น 14,009',
              suffixText: 'หน่วย',
              icon: Icons.bolt,
              iconColor: Colors.orange,
            ),
          const SizedBox(height: 12),
          _field(
            controller: waterCtrl,
            label: 'เลขมิเตอร์น้ำ',
            hint: 'เช่น 148',
            suffixText: 'หน่วย',
            icon: Icons.water_drop,
            iconColor: Colors.blue,
          ),
        ],
      ),
    );
  }
}