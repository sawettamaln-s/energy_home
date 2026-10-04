import 'package:flutter/material.dart';

import '../../../widgets/ui/app_card.dart';
import '../../../widgets/ui/icon_badge.dart';
import '../dashboard_styles.dart';

// =====================================================================
// การ์ดเช็คลิสต์ "เริ่มต้นใช้งาน 3 ขั้นตอน" — แสดงแทนการ์ดมิเตอร์ตอนที่ยังไม่ได้
// ตั้งเลขมิเตอร์ต้นรอบเลยสักฝั่ง แต่ละขั้นกดแล้วพาไปหน้านั้นได้ทันที ลำดับตรงกับ
// คู่มือและเมนูในหน้าตั้งค่า:
//   1) วันตัดรอบบิล — ติ๊กถูกเมื่อผู้ใช้เลือกวันเองแล้ว (billingDayDone)
//   2) เลขมิเตอร์จากใบแจ้งหนี้ — ทำเสร็จแล้วการ์ดนี้จะหายไป
//   3) บิลเดือนเก่า (ไม่บังคับ) — ไม่มีติ๊กถูก เพราะทำหรือไม่ทำก็ได้
// แถบความคืบหน้านับเฉพาะ 2 ขั้นที่จำเป็น
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
    final doneRequired = billingDayDone ? 1 : 0;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(
                  icon: Icons.checklist_rounded, color: AppColors.primaryGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'เริ่มต้นใช้งาน 3 ขั้นตอน',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppTypography.s15),
                    ),
                    Text(
                      'เตรียมใบแจ้งหนี้ใบล่าสุดไว้ได้เลยค่ะ',
                      style: TextStyle(
                          fontSize: AppTypography.s12,
                          color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: doneRequired / 2,
                    minHeight: 6,
                    backgroundColor:
                        AppColors.primaryGreen.withValues(alpha: 0.1),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('ทำแล้ว $doneRequired/2',
                  style: TextStyle(
                      fontSize: AppTypography.s11_5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ทำขั้นที่ 1–2 ให้ครบ หน้าหลักจะเริ่มคำนวณค่าไฟ/ค่าน้ำให้ค่ะ',
            style: TextStyle(
                fontSize: AppTypography.s11_5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          _SetupStep(
            number: 1,
            title: 'ตั้งวันตัดรอบบิล',
            description: 'เลือกวันที่จดเลขมิเตอร์บนใบแจ้งหนี้',
            done: billingDayDone,
            highlight: !billingDayDone,
            onTap: onBillingDay,
          ),
          _SetupStep(
            number: 2,
            title: 'เลขมิเตอร์จากใบแจ้งหนี้',
            description: 'กรอกเลขมิเตอร์และยอดเงินจากใบแจ้งหนี้ล่าสุด',
            done: false,
            highlight: billingDayDone,
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

// แถวขั้นตอนในการ์ดเช็คลิสต์ — วงกลมเลขขั้น (เสร็จแล้วเป็นติ๊กถูก) + ชื่อขั้น
// + คำอธิบายสั้น แตะทั้งแถวเพื่อไปทำขั้นนั้น [highlight] = ขั้นถัดไปที่ควรทำ
class _SetupStep extends StatelessWidget {
  final int number;
  final String title;
  final String description;
  final bool done;
  final bool highlight;
  final VoidCallback onTap;

  const _SetupStep({
    required this.number,
    required this.title,
    required this.description,
    required this.done,
    this.highlight = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done || highlight
                    ? AppColors.primaryGreen
                    : AppColors.primaryGreen.withValues(alpha: 0.1),
              ),
              child: done
                  ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                  : Text('$number',
                      style: TextStyle(
                          fontSize: AppTypography.s12_5,
                          fontWeight: FontWeight.w700,
                          color: highlight
                              ? Colors.white
                              : AppColors.primaryGreen)),
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
                        color: done ? Colors.grey.shade500 : AppColors.textDark,
                        decoration: done ? TextDecoration.lineThrough : null,
                      )),
                  const SizedBox(height: 2),
                  Text(done ? 'ตั้งแล้ว แตะเพื่อเปลี่ยน' : description,
                      style: TextStyle(
                          fontSize: AppTypography.s11_5,
                          color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
