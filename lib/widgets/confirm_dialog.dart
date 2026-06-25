import 'package:flutter/material.dart';

/// Dialog ยืนยันแบบ "ยกเลิก / ยืนยัน(สีแดง)" ที่ใช้ซ้ำทั่วแอป
/// (เดิมก็อปวางโครงเดิมซ้ำ 7 ที่ใน settings_screen.dart และ appliance_screen.dart)
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmLabel = 'ลบ',
  String cancelLabel = 'ยกเลิก',
  Color confirmColor = Colors.red,
  double? borderRadius,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: borderRadius != null
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius))
          : null,
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel, style: TextStyle(color: confirmColor)),
        ),
      ],
    ),
  );
  return result ?? false;
}