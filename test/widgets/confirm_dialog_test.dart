// เทส showConfirmDialog (lib/widgets/confirm_dialog.dart) — dialog
// "ยกเลิก / ยืนยัน(สีแดง)" ที่ใช้ซ้ำทั่วแอปสำหรับ action ที่ทำลายข้อมูล
// (เช่น ลบ log, ลบรายการค่าใช้จ่ายคงที่)
//
// ครอบ 3 เคสหลัก:
//   1) กดปุ่มยืนยัน -> Future คืนค่า true
//   2) กดปุ่มยกเลิก -> Future คืนค่า false
//   3) ปิด dialog โดยไม่กดปุ่มไหนเลย (เช่น กด back) -> คืนค่า false ไม่ใช่ null
//      (ดูโค้ด: `return result ?? false;`)
import 'package:energy_home/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildAppWithButton(ValueChanged<bool> onResult) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              final result = await showConfirmDialog(
                context,
                title: 'ลบรายการนี้?',
                content: 'ลบแล้วกู้คืนไม่ได้',
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('กดปุ่มยืนยัน (ค่า default = "ลบ") -> คืนค่า true',
      (tester) async {
    bool? result;
    await tester.pumpWidget(buildAppWithButton((r) => result = r));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ลบรายการนี้?'), findsOneWidget);
    expect(find.text('ลบแล้วกู้คืนไม่ได้'), findsOneWidget);

    await tester.tap(find.text('ลบ'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.text('ลบรายการนี้?'), findsNothing);
  });

  testWidgets('กดปุ่มยกเลิก -> คืนค่า false', (tester) async {
    bool? result;
    await tester.pumpWidget(buildAppWithButton((r) => result = r));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('รองรับ label/สีปุ่มยืนยันแบบกำหนดเอง', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showConfirmDialog(
              context,
              title: 'ออกจากระบบ?',
              content: 'ต้องเข้าสู่ระบบใหม่อีกครั้ง',
              confirmLabel: 'ออกจากระบบ',
              confirmColor: Colors.orange,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ออกจากระบบ'), findsOneWidget);
    final button = tester.widget<Text>(find.text('ออกจากระบบ'));
    expect(button.style?.color, Colors.orange);
  });
}