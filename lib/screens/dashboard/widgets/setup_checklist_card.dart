import 'package:flutter/material.dart';

import '../dashboard_styles.dart';

// =====================================================================
// การ์ดเช็คลิสต์ "เริ่มต้นใช้งาน 3 ขั้นตอน" — แสดงแทนการ์ดมิเตอร์ตอนที่ยังไม่ได้
// ตั้งเลขมิเตอร์ต้นรอบเลยสักฝั่ง แต่ละขั้นกดแล้วพาไปหน้านั้นได้ทันที ลำดับตรงกับ
// คู่มือและเมนูในหน้าตั้งค่า:
//   1) วันตัดรอบบิล — ติ๊กถูกเมื่อผู้ใช้เลือกวันเองแล้ว (billingDayDone)
//   2) เลขมิเตอร์จากใบแจ้งหนี้ — ทำเสร็จแล้วการ์ดนี้จะหายไป
//   3) บิลเดือนเก่า (ไม่บังคับ) — ไม่มีติ๊กถูก เพราะทำหรือไม่ทำก็ได้
// ระหว่างนี้ห้ามบันทึกมิเตอร์รายวัน เพราะถ้าไม่มีเลขตั้งต้น ระบบจะเอาเลข
// มิเตอร์สะสมทั้งก้อน (เช่น 15,234 หน่วย) ไปนับเป็น "หน่วยที่ใช้รอบนี้"
// =====================================================================
class SetupChecklistCard extends StatelessWidget {
  final bool billingDayDone;
  final VoidCallback onBillingDay;
  final VoidCallback onStartMeter;
  final VoidCallback onPastBills;

  const SetupChecklistCard({
    super.key,
    required this.billingDayDone,
    required this.onBillingDay,
    required this.onStartMeter,
    required this.onPastBills,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v14),
        border: Border.all(
            color: DashboardStyles.primaryGreen.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.v8),
                decoration: BoxDecoration(
                  color: DashboardStyles.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.v8),
                ),
                child: const Icon(Icons.checklist_rounded,
                    color: DashboardStyles.primaryGreen, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'เริ่มต้นใช้งาน 3 ขั้นตอน',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: AppTypography.s14_5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ทำขั้นที่ 1–2 ให้ครบ หน้าหลักจะเริ่มคำนวณค่าไฟ/ค่าน้ำให้ค่ะ '
            'เตรียมใบแจ้งหนี้ใบล่าสุดไว้ได้เลย',
            style: TextStyle(
                fontSize: AppTypography.s12_5,
                color: Colors.grey.shade600,
                height: 1.5),
          ),
          const SizedBox(height: 12),
          _SetupStep(
            number: 1,
            title: 'ตั้งวันตัดรอบบิล',
            description: 'เลือกวันที่จดเลขมิเตอร์บนใบแจ้งหนี้',
            done: billingDayDone,
            onTap: onBillingDay,
          ),
          _SetupStep(
            number: 2,
            title: 'เลขมิเตอร์จากใบแจ้งหนี้',
            description: 'กรอกเลขมิเตอร์และยอดเงินจากใบแจ้งหนี้ล่าสุด',
            done: false,
            onTap: onStartMeter,
          ),
          _SetupStep(
            number: 3,
            title: 'เพิ่มบิลเดือนเก่า (ไม่บังคับ)',
            description: 'ย้อนหลังได้ 5 เดือน ให้หน้าวิเคราะห์มีข้อมูลทันที',
            done: false,
            onTap: onPastBills,
          ),
        ],
      ),
    );
  }
}

// แถวขั้นตอนในการ์ดเช็คลิสต์ — วงกลมเลขขั้น (เสร็จแล้วเป็นติ๊กถูก) +
// ชื่อขั้น + คำอธิบายสั้น แตะทั้งแถวเพื่อไปทำขั้นนั้น
class _SetupStep extends StatelessWidget {
  final int number;
  final String title;
  final String description;
  final bool done;
  final VoidCallback onTap;

  const _SetupStep({
    required this.number,
    required this.title,
    required this.description,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.v10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.v8),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done
                    ? DashboardStyles.primaryGreen
                    : DashboardStyles.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: done
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : Text('$number',
                      style: const TextStyle(
                          fontSize: AppTypography.s12_5,
                          fontWeight: FontWeight.bold,
                          color: DashboardStyles.primaryGreen)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: AppTypography.s13_5,
                        fontWeight: FontWeight.w600,
                        color: done
                            ? Colors.grey.shade500
                            : DashboardStyles.textDark,
                      )),
                  const SizedBox(height: 2),
                  Text(done ? 'ตั้งแล้ว แตะเพื่อเปลี่ยน' : description,
                      style: TextStyle(
                          fontSize: AppTypography.s11_5,
                          color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}
