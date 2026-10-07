import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/dashboard/dashboard_styles.dart';
import '../utils/calculator.dart';

/// ===========================================================
/// OnboardingGuide
/// พาร์ทนี้ทำหน้าที่: แสดง dialog คู่มือเริ่มต้นใช้งานให้ผู้ใช้ใหม่
/// "ครั้งแรกที่เข้า Dashboard" เท่านั้น อธิบายว่าระบบรอบบิล/การ
/// บันทึกมิเตอร์/การบันทึกบิลย้อนหลังทำงานยังไง เพื่อให้เข้าใจก่อนใช้งานจริง
/// ใช้ SharedPreferences กันไม่ให้โผล่ซ้ำหลังจากปิดไปแล้วครั้งหนึ่ง
/// ===========================================================
class OnboardingGuide {
  static const String _prefKey = 'has_seen_onboarding_guide';

  /// เรียกจาก DashboardScreen หลังโหลดข้อมูลรอบแรก (ต้องรู้ [area]/[meterType] ของ
  /// ผู้ใช้ก่อน เพื่อบอกรหัสประเภทอัตราค่าไฟให้ตรงการไฟฟ้า) เช็คก่อนว่าเคยเห็นคู่มือนี้
  /// แล้วหรือยัง ถ้ายังไม่เคย ค่อยแสดง dialog
  static Future<void> showIfFirstTime(BuildContext context, {String? area, String? meterType}) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_prefKey) ?? false;
    if (hasSeen) return;
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OnboardingDialog(area: area, meterType: meterType),
    );

    await prefs.setBool(_prefKey, true);
  }
}

class _OnboardingDialog extends StatefulWidget {
  final String? area;
  final String? meterType;

  const _OnboardingDialog({this.area, this.meterType});

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  int _page = 0;

  // เนื้อหาคู่มือ 3 หน้า: แอปทำอะไร / ตั้งค่าเริ่มต้น 3 ขั้น / ใช้งานประจำวัน
  // (ชื่อหมวด/เมนูต้องตรงกับหน้าตั้งค่า: ขั้น 1 อยู่หมวด "รอบบิลและค่าใช้จ่าย" ขั้น 2-3
  // อยู่หมวด "ข้อมูลมิเตอร์และบิล" และตรงกับการ์ดเช็คลิสต์บนหน้าหลัก)
  late final List<_GuidePage> _pages = [
    const _GuidePage(
      icon: Icons.waving_hand_rounded,
      title: 'ยินดีต้อนรับสู่ Energy Home ค่ะ',
      body:
          'แอปนี้ช่วยติดตามค่าไฟ-ค่าน้ำของบ้านคุณแบบรายรอบบิล '
          'คาดการณ์ยอดก่อนบิลจริงจะมา และวิเคราะห์ว่าเดือนนี้ใช้มากหรือน้อย'
          'กว่าปกติ\n\n'
          'ก่อนเริ่ม เตรียมใบแจ้งหนี้ค่าไฟ/ค่าน้ำใบล่าสุดไว้ใกล้ๆ นะคะ',
    ),
    _GuidePage(
      icon: Icons.checklist_rounded,
      title: 'ตั้งค่าเริ่มต้น 3 ขั้นตอน',
      body:
          'กดทำตามการ์ดเช็คลิสต์บนหน้าหลัก หรือไปที่แท็บ "ตั้งค่า"\n\n'
          '1. วันตัดรอบบิล (หมวด "รอบบิลและค่าใช้จ่าย") — เลือกวันที่จดเลขมิเตอร์'
          'บนใบแจ้งหนี้\n'
          '2. เลขมิเตอร์จากใบแจ้งหนี้ (หมวด "ข้อมูลมิเตอร์และบิล") — กรอกเลขมิเตอร์'
          'และยอดเงินจากใบแจ้งหนี้ล่าสุด ใช้เป็นจุดเริ่มคำนวณ\n'
          '3. บิลย้อนหลัง (อยู่ในหน้าเดียวกัน ไม่บังคับ) — '
          'ย้อนหลังได้ 5 เดือน ให้หน้าวิเคราะห์มีข้อมูลเปรียบเทียบตั้งแต่วันแรก',
      note: _tariffNote(),
    ),
    const _GuidePage(
      icon: Icons.edit_note_rounded,
      title: 'ใช้งานประจำวัน',
      body:
          'บันทึกเลขมิเตอร์ที่หน้าหลักเป็นประจำ ยิ่งบันทึกบ่อย ยอดคาดการณ์'
          'สิ้นรอบในหน้าวิเคราะห์ยิ่งแม่นยำ\n\n'
          'เพิ่ม "รายจ่ายประจำ" (ค่าส่วนกลาง อินเทอร์เน็ต ฯลฯ) เพื่อรวมเป็นยอดทั้งหมด'
          'ของเดือน และบันทึก "อุปกรณ์" เพื่อดูว่าค่าไฟส่วนใหญ่มาจากเครื่องไหน\n\n'
          'แอปจะแจ้งเตือนเมื่อถึงวันตัดรอบ ไม่ได้บันทึกนาน ค่าใช้จ่ายพุ่งผิดปกติ '
          'และสรุปยอดเมื่อปิดรอบบิล (เปิด/ปิดได้ที่หน้าตั้งค่า)',
    ),
  ];

  // หมายเหตุประเภทอัตราค่าไฟ — ประเภทขึ้นกับขนาดมิเตอร์ แอปตั้งค่าเริ่มต้นเป็นประเภท
  // ของบ้านส่วนใหญ่ (มิเตอร์ใหญ่กว่า 5 แอมแปร์) รหัสต่างกันตามการไฟฟ้าจึงต้องรู้ area
  // มิเตอร์ TOU มีอัตราของตัวเอง ไม่ต้องเลือกประเภท จึงไม่แสดง
  String? _tariffNote() {
    final area = widget.area;
    if (area == null || widget.meterType == null || widget.meterType == 'tou') return null;
    final standard = EnergyCalculator.tariffCode(EnergyCalculator.tariffStandard, area);
    final small = EnergyCalculator.tariffCode(EnergyCalculator.tariffSmall, area);
    return 'ตรวจเพิ่มเติม: แอปตั้งประเภทอัตราค่าไฟไว้ที่ $standard ของบ้านส่วนใหญ่ '
        'ถ้าใบแจ้งหนี้ระบุ $small (มิเตอร์ไม่เกิน 5 แอมแปร์) เปลี่ยนได้ที่ '
        '"ประเภทอัตราค่าไฟ" ในหมวด "รอบบิลและค่าใช้จ่าย" ค่ะ';
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];
    final isLast = _page == _pages.length - 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v20)),
      // เลื่อนได้เมื่อเนื้อหาสูงกว่าจอ (จอเล็กหรือตัวอักษรใหญ่)
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.v24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(page.icon, color: DashboardStyles.primaryGreen, size: 36),
            const SizedBox(height: 14),
            Text(
              page.title,
              style: const TextStyle(
                fontSize: AppTypography.s17,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              page.body,
              style: const TextStyle(
                fontSize: AppTypography.s13_5,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
            if (page.note != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(AppSpacing.v10),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppSpacing.v10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.primaryGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        page.note!,
                        style: const TextStyle(
                            fontSize: AppTypography.s12_5, height: 1.5, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // จุดบอกความคืบหน้า (เหมือน dot indicator)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.v3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? DashboardStyles.primaryGreen
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(AppSpacing.v3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),

            // จอแคบหรือตัวอักษรใหญ่จนปุ่มไม่พอแถวเดียว จะเรียงลงเป็นแนวตั้งแทนการล้น
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              overflowSpacing: 4,
              children: [
                if (_page > 0)
                  TextButton(
                    onPressed: () => setState(() => _page--),
                    child: const Text('ย้อนกลับ'),
                  )
                else
                  const SizedBox.shrink(),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (!isLast)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('ข้าม',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DashboardStyles.primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.v10),
                        ),
                      ),
                      onPressed: () {
                        if (isLast) {
                          Navigator.of(context).pop();
                        } else {
                          setState(() => _page++);
                        }
                      },
                      child: Text(isLast ? 'เข้าใจแล้ว' : 'ถัดไป'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePage {
  final IconData icon;
  final String title;
  final String body;
  final String? note; // กล่องหมายเหตุใต้เนื้อหา (ไม่มี = ไม่แสดง)

  const _GuidePage({
    required this.icon,
    required this.title,
    required this.body,
    this.note,
  });
}