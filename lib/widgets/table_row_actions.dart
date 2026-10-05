import 'package:flutter/material.dart';

import '../styles/app_spacing.dart';
import '../styles/app_typography.dart';

// เมนูแก้ไข/ลบ เวลาแตะแถวในตารางประวัติ (บิลย้อนหลัง, ประวัติการบันทึกมิเตอร์)
// — ถ้า locked โชว์ข้อความอธิบายแทนเมนู (bottom sheet มุมโค้งบน) รวมเป็น helper
// กลางจุดเดียว ไม่ต้องเขียนซ้ำทุกหน้า
Future<void> showTableRowActions(
  BuildContext context, {
  required String title,
  String? subtitle,
  bool locked = false,
  String lockedMessage = 'รายการนี้อยู่ในรอบบิลที่ปิดไปแล้ว ถูกใช้คำนวณ'
      'เรียบร้อยแล้ว จึงแก้ไข/ลบไม่ได้ เพื่อไม่ให้ตัวเลขเก่ากับ'
      'ประวัติไม่ตรงกัน',
  String? lockedActionLabel,
  VoidCallback? onLockedAction,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) async {
  if (locked) {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขไม่ได้แล้ว'),
        content: Text(lockedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('เข้าใจแล้ว'),
          ),
          if (onLockedAction != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onLockedAction();
              },
              child: Text(lockedActionLabel ?? 'ไปที่หน้านั้น'),
            ),
        ],
      ),
    );
    return;
  }

  await showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.v20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(AppSpacing.v2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v14, AppSpacing.v20, AppSpacing.v6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.s15),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          if (onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('แก้ไขรายการนี้'),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
          if (onDelete != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: Text('ลบรายการนี้',
                  style: TextStyle(color: Colors.red.shade400)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}