import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ===========================================================
/// OnboardingGuide
/// พาร์ทนี้ทำหน้าที่: แสดง dialog คู่มือเริ่มต้นใช้งานให้ผู้ใช้ใหม่
/// "ครั้งแรกที่เข้า Dashboard" เท่านั้น อธิบายว่าระบบรอบบิล/การ
/// บันทึกมิเตอร์/การบันทึกบิลย้อนหลังทำงานยังไง เพื่อให้เข้าใจก่อนใช้งานจริง
/// ใช้ SharedPreferences กันไม่ให้โผล่ซ้ำหลังจากปิดไปแล้วครั้งหนึ่ง
/// ===========================================================
class OnboardingGuide {
  static const String _prefKey = 'has_seen_onboarding_guide';

  /// เรียกจาก initState ของ DashboardScreen (หรือหน้าแรกหลัง Setup Wizard)
  /// เช็คก่อนว่าเคยเห็นคู่มือนี้แล้วหรือยัง ถ้ายังไม่เคย ค่อยแสดง dialog
  static Future<void> showIfFirstTime(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_prefKey) ?? false;
    if (hasSeen) return;
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _OnboardingDialog(),
    );

    await prefs.setBool(_prefKey, true);
  }

  /// เรียกตอนผู้ใช้กดเปิดคู่มือเองซ้ำ (เช่น กดปุ่มกระดิ่งที่หัว Dashboard)
  /// ไม่เช็ค flag ใด ๆ เปิดได้เสมอไม่ว่าจะเคยเห็นมาก่อนหรือไม่
  static Future<void> showAgain(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _OnboardingDialog(),
    );
  }
}

class _OnboardingDialog extends StatefulWidget {
  const _OnboardingDialog();

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  int _page = 0;

  // เนื้อหาคู่มือ แบ่งเป็นหน้าๆ ให้อ่านง่าย ไม่ยัดทุกอย่างไว้หน้าเดียว
  final List<_GuidePage> _pages = const [
    _GuidePage(
      icon: Icons.waving_hand_rounded,
      title: 'ยินดีต้อนรับสู่ Energy Home 👋',
      body:
          'แอปนี้ช่วยติดตามค่าไฟและค่าน้ำในบ้าน โดยคำนวณจาก "รอบบิล" '
          'ที่พอดีตั้งวันตัดรอบไว้ตอน Setup (เช่น ตัดรอบทุกวันที่ 5 ของเดือน) '
          'ทุกอย่างในแอปจะอ้างอิงตามรอบนี้เป็นหลัก',
    ),
    _GuidePage(
      icon: Icons.edit_note_rounded,
      title: 'บันทึกมิเตอร์ทุกวัน ทำไมสำคัญ?',
      body:
          'ยิ่งบันทึกค่ามิเตอร์บ่อย (แนะนำทุกวัน) ระบบจะคำนวณ "ค่าเฉลี่ยการใช้ต่อวัน" '
          'ได้แม่นยำขึ้น ซึ่งใช้พยากรณ์ยอดค่าไฟ-น้ำสิ้นเดือนล่วงหน้า '
          'ถ้าไม่บันทึกนานเกินไป แอปจะเตือนให้กลับมาบันทึก',
    ),
    _GuidePage(
      icon: Icons.history_rounded,
      title: 'บันทึกบิลย้อนหลัง ใช้ทำอะไร?',
      body:
          'ถ้าพอดีมีบิลเดือนก่อน ๆ ที่ยังไม่ได้กรอกไว้ในระบบ สามารถเพิ่มย้อนหลังได้ '
          'ข้อมูลนี้สำคัญเพราะแอปใช้ "ยอดเดือนก่อน" มาเทียบกับเดือนนี้ เพื่อบอกว่า '
          'ค่าใช้จ่ายตอนนี้พุ่งขึ้นกว่าปกติหรือเปล่า ถ้าไม่มีข้อมูลเดือนก่อนเลย '
          'ระบบจะยังไม่สามารถเตือนเรื่องนี้ได้',
    ),
    _GuidePage(
      icon: Icons.bookmark_outline_rounded,
      title: 'Fixed Cost คืออะไร?',
      body:
          'คือค่าใช้จ่ายประจำที่ไม่เกี่ยวกับมิเตอร์ เช่น ค่าส่วนกลาง ค่าอินเทอร์เน็ต '
          'ตั้งไว้ในหน้า "ตั้งค่า" ระบบจะรวมเข้ากับค่าไฟ-น้ำให้อัตโนมัติทุกเดือน',
    ),
    _GuidePage(
      icon: Icons.notifications_active_rounded,
      title: 'แจ้งเตือนที่ควรรู้',
      body:
          '• ใกล้วันตัดรอบบิล (เตือนล่วงหน้า 3 วัน)\n'
          '• ยังไม่ได้บันทึกมิเตอร์นานเกินไป\n'
          '• ใช้ไฟ/น้ำพุ่งขึ้นเกิน 30% จากเดือนก่อน\n'
          '• สรุปยอดทันทีที่ปิดรอบบิลเสร็จ\n\n'
          'พร้อมแล้ว ลองเริ่มบันทึกมิเตอร์แรกของพอดีได้เลย!',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];
    final isLast = _page == _pages.length - 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(page.icon, color: const Color(0xFF2E7D32), size: 36),
            const SizedBox(height: 14),
            Text(
              page.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              page.body,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Color(0xFF555555),
              ),
            ),
            const SizedBox(height: 20),

            // จุดบอกความคืบหน้า (เหมือน dot indicator)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF2E7D32)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                if (_page > 0)
                  TextButton(
                    onPressed: () => setState(() => _page--),
                    child: const Text('ย้อนกลับ'),
                  ),
                const Spacer(),
                if (!isLast)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ข้าม',
                        style: TextStyle(color: Colors.grey)),
                  ),
                const SizedBox(width: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }
}

class _GuidePage {
  final IconData icon;
  final String title;
  final String body;

  const _GuidePage({
    required this.icon,
    required this.title,
    required this.body,
  });
}