import 'package:flutter/material.dart';

// ==================== ตารางสไตล์ Excel ====================
// ใช้แทน timeline-card เดิมในหน้า "เลขมิเตอร์ต้นรอบ", "บันทึกบิลย้อนหลัง",
// "ประวัติมิเตอร์ไฟฟ้า/ประปา" — โชว์เป็นคอลัมน์ตรงๆ แบบเว็บการไฟฟ้า/ประปา
// อ่านง่ายกว่าการ์ดที่มี chip เยอะๆ โดยเฉพาะเวลามีหลายรายการ
//
// แถวแตะได้ (onRowTap) เพื่อเปิดเมนู แก้ไข/ลบ แทนการใส่ปุ่มเต็มๆ ในแถว
// (ตารางแคบเกินจะใส่ไอคอนหลายอันต่อแถวให้ดูโล่ง) ใช้คู่กับ
// showTableRowActions ด้านล่าง

class ExcelTableColumn {
  final String label;
  final TextAlign align;
  final int flex;

  const ExcelTableColumn(
    this.label, {
    this.align = TextAlign.right,
    this.flex = 1,
  });
}

class ExcelStyleTable extends StatelessWidget {
  final Color accent;
  final List<ExcelTableColumn> columns;
  final int rowCount;
  final String Function(int row, int col) cellText;
  final bool Function(int row)? isLatest;
  final bool Function(int row)? isLocked;
  final void Function(int row)? onRowTap;

  const ExcelStyleTable({
    super.key,
    required this.accent,
    required this.columns,
    required this.rowCount,
    required this.cellText,
    this.isLatest,
    this.isLocked,
    this.onRowTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _headerRow(),
            for (int row = 0; row < rowCount; row++) _dataRow(context, row),
          ],
        ),
      ),
    );
  }

  Widget _headerRow() {
    return Container(
      color: accent.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          for (final c in columns)
            Expanded(
              flex: c.flex,
              child: Text(
                c.label,
                textAlign: c.align,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataRow(BuildContext context, int row) {
    final latest = isLatest?.call(row) ?? false;
    final locked = isLocked?.call(row) ?? false;
    final bg = latest
        ? accent.withValues(alpha: 0.06)
        : (row.isOdd ? Colors.grey.shade50 : Colors.white);

    return InkWell(
      onTap: onRowTap == null ? null : () => onRowTap!(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            for (int col = 0; col < columns.length; col++)
              Expanded(
                flex: columns[col].flex,
                child: Row(
                  mainAxisAlignment: columns[col].align == TextAlign.right
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: [
                    if (col == 0 && locked)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.lock_outline,
                            size: 12, color: Colors.grey.shade400),
                      ),
                    Flexible(
                      child: Text(
                        cellText(row, col),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              col == 0 && latest ? FontWeight.bold : FontWeight.normal,
                          color: col == 0
                              ? Colors.black87
                              : Colors.black.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// แถบสรุปเล็กด้านบนตาราง (จำนวนรายการ) ใช้ร่วมกันได้ทุกหน้า
Widget excelTableEmptyState({
  required IconData icon,
  required String message,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    ),
  );
}

// เมนูแก้ไข/ลบ เวลาแตะแถวในตาราง — ถ้า locked โชว์ข้อความอธิบายแทนเมนู
// เป็นแพทเทิร์นเดียวกับที่ใช้ทั่วแอป (bottom sheet มุมโค้งบน) แค่รวมเป็น
// helper กลางจุดเดียว ไม่ต้องเขียนซ้ำ 3 ที่
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
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