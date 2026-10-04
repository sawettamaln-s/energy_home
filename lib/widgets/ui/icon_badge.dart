import 'package:flutter/material.dart';

// ไอคอนในกรอบสี่เหลี่ยมมนสีจาง — ใช้นำหน้าหัวการ์ด/แถวรายการทั้งแอป ให้มี
// จุดนำสายตาและบอกหมวดด้วยสี (ไฟฟ้า/น้ำ/ทั่วไป)
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size; // ความกว้าง/สูงของกรอบ
  final Color? background; // ไม่ส่ง = สีเดียวกับไอคอนแบบจาง

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}
