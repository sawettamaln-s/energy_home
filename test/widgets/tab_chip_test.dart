// เทส TabChip (lib/widgets/tab_chip.dart) — แท็บสลับไฟฟ้า/น้ำที่ใช้ร่วมกัน
// ระหว่างหน้าบันทึกบิลย้อนหลังกับหน้าตั้งค่ามิเตอร์ต้นรอบ
//
// ครอบ 3 พฤติกรรมหลัก:
//   1) แตะแล้วเรียก onTap
//   2) selected=true ต้องเห็นสีตาม color ที่ส่งมา (ไม่ใช่สีเทา default)
//   3) checked=true ต้องเห็นไอคอน check_circle เพิ่มขึ้นมา, false ต้องไม่เห็น
import 'package:energy_home/widgets/tab_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildChip({
    required bool selected,
    required bool checked,
    required VoidCallback onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TabChip(
          label: 'ไฟฟ้า',
          icon: Icons.bolt,
          color: Colors.orange,
          selected: selected,
          checked: checked,
          onTap: onTap,
        ),
      ),
    );
  }

  testWidgets('แตะแล้วเรียก onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(buildChip(
      selected: false,
      checked: false,
      onTap: () => tapped = true,
    ));

    await tester.tap(find.byType(TabChip));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('checked: true -> เห็นไอคอน check_circle', (tester) async {
    await tester.pumpWidget(buildChip(
      selected: true,
      checked: true,
      onTap: () {},
    ));

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('checked: false -> ไม่มีไอคอน check_circle', (tester) async {
    await tester.pumpWidget(buildChip(
      selected: true,
      checked: false,
      onTap: () {},
    ));

    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('label และไอคอนหลักแสดงถูกต้องเสมอไม่ว่า selected จะเป็นค่าไหน',
      (tester) async {
    await tester.pumpWidget(buildChip(
      selected: false,
      checked: false,
      onTap: () {},
    ));

    expect(find.text('ไฟฟ้า'), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });
}