import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/dashboard/dashboard_styles.dart';

// =====================================================================
// AppTopBar — แถบด้านบนมาตรฐานของทั้งแอป (ยกเว้นหน้าบันทึกมิเตอร์ที่ตั้งใจ
// ใช้สี accent เฉพาะของตัวเอง ไม่ใช้ widget นี้)
//
// ก่อนหน้านี้แต่ละหน้า (การแจ้งเตือน, อุปกรณ์, ตั้งค่า, รายจ่ายประจำ,
// บันทึกเลขมิเตอร์ประจำเดือน, เพิ่มบิลเดือนเก่าเข้าระบบ, ประวัติการบันทึก
// มิเตอร์, อัตราค่าไฟฟ้า/น้ำ ฯลฯ) ต่างประกอบ AppBar เองแยกไฟล์ ทำให้
// ชื่อหน้าบางหน้าชิดซ้าย บางหน้ากึ่งกลาง ฟอนต์บางหน้าหนา บางหน้าปกติ
// ไอคอนย้อนกลับบางหน้าเป็นลูกศรเต็มหัว (Material default) บางหน้าไม่มี —
// รวม logic เหล่านี้มาไว้ที่เดียวเหมือนที่ DashboardStyles ทำกับสีหลักของ
// แอป แก้ที่นี่ที่เดียวมีผลทุกหน้าที่เรียกใช้
//
// กติกาที่ล็อกไว้:
//   - ชื่อหน้าอยู่กึ่งกลางเสมอ ฟอนต์ 16px น้ำหนัก 600 สีขาว
//   - ชื่อยาวเกินพื้นที่ว่าง (กรณีมี leading+actions มาแย่งพื้นที่) จะลด
//     ขนาดฟอนต์ลงอัตโนมัติผ่าน FittedBox แทนการตัดจบด้วย "..." เพื่อให้
//     ยังอ่านชื่อเต็มได้เสมอไม่ว่าชื่อหน้าจะยาวแค่ไหน
//   - ไอคอนย้อนกลับเป็นเชฟรอนล้วนไม่มีพื้นหลัง (แบบเดียวกับหน้าบันทึก
//     มิเตอร์) แทนลูกศรเต็มหัวแบบ Material default
// =====================================================================
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  // ปิดปุ่มย้อนกลับสำหรับหน้าหลักที่เข้าถึงผ่าน bottom nav โดยตรง
  // (แดชบอร์ด, วิเคราะห์, อุปกรณ์, ตั้งค่า) ซึ่งไม่มีหน้าให้ pop กลับไป
  final bool showBack;
  final Color? backgroundColor;

  const AppTopBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.showBack = true,
    this.backgroundColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(
      kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: backgroundColor ?? DashboardStyles.primaryGreen,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.chevron_left, size: 26, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      title: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          title,
          maxLines: 1,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}