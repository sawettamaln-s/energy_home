import 'package:flutter/material.dart';

/// ก้อนไอคอน + ตัวเลขเล็กๆ ใช้โชว์ค่าสรุปในการ์ด (เช่น หน่วยไฟฟ้า, ค่าไฟ,
/// ค่ามิเตอร์เริ่มต้น) — ดีไซน์เดียวกันหมด ใช้ซ้ำใน 4 ที่: ประวัติบิล,
/// ประวัติมิเตอร์ต้นรอบ, ประวัติมิเตอร์ไฟฟ้า, ประวัติมิเตอร์น้ำ
///
/// เดิมแต่ละหน้ามี `Widget _valueChip(...)` แบบ private ก๊อปวางเหมือนกันเป๊ะ
/// อยู่ 4 จุดใน settings_screen.dart รวมกันแล้วตรงกันทุกตัวอักษร รวมมาไว้
/// เป็น widget กลางที่นี่ที่เดียว แก้ดีไซน์ทีเดียวมีผลทุกที่ที่ใช้
class ValueChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const ValueChip({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            '$label $value',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}