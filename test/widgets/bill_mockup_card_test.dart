// เทส BillMockupCard (lib/widgets/bill_mockup_card.dart) — การ์ดตัวอย่างบิล
// ไฟฟ้า/น้ำ (mock) ที่เลือกผู้ให้บริการอัตโนมัติจาก area และโครงสร้างตาราง
// จาก isTou ตามที่อธิบายไว้ใน lib/widgets/bill_mockup_card.dart
//
// ครอบว่าแต่ละ combination ของ (isElectricity, area, isTou) เลือกผู้
// ให้บริการ/โครงสร้างตารางถูกต้อง — เป็นจุดที่เคยมีบั๊กสีของ estimated-cost
// banner ผสมกันระหว่างไฟฟ้า/น้ำ จึงคุ้มค่าที่จะมีเทส regression กันไว้
//
// ห่อด้วย SingleChildScrollView เพราะการ์ดค่อนข้างสูง เพื่อไม่ให้เกิด
// RenderFlex overflow ตอนเทสใน viewport ขนาดเล็ก
import 'package:energy_home/widgets/bill_mockup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  testWidgets('ไฟฟ้า + bangkok + ปกติ (ไม่ใช่ TOU) -> ใช้ MEA', (tester) async {
    await tester.pumpWidget(wrap(const BillMockupCard(
      isElectricity: true,
      area: 'bangkok',
    )));

    expect(find.textContaining('MEA'), findsWidgets);
    expect(find.textContaining('การไฟฟ้านครหลวง'), findsOneWidget);
    expect(find.textContaining('On-Peak'), findsNothing);
  });

  testWidgets('ไฟฟ้า + province + ปกติ -> ใช้ PEA', (tester) async {
    await tester.pumpWidget(wrap(const BillMockupCard(
      isElectricity: true,
      area: 'province',
    )));

    expect(find.textContaining('PEA'), findsWidgets);
    expect(find.textContaining('การไฟฟ้าส่วนภูมิภาค'), findsOneWidget);
  });

  testWidgets('ไฟฟ้า + bangkok + TOU -> ใช้ MEA พร้อมตาราง On-Peak/Off-Peak',
      (tester) async {
    await tester.pumpWidget(wrap(const BillMockupCard(
      isElectricity: true,
      area: 'bangkok',
      isTou: true,
    )));

    expect(find.textContaining('MEA'), findsWidgets);
    expect(find.text('On-Peak'), findsOneWidget);
    expect(find.text('Off-Peak'), findsOneWidget);
  });

  testWidgets('ไฟฟ้า + province + TOU -> ใช้ PEA พร้อมตาราง On-Peak/Off-Peak',
      (tester) async {
    await tester.pumpWidget(wrap(const BillMockupCard(
      isElectricity: true,
      area: 'province',
      isTou: true,
    )));

    expect(find.textContaining('PEA'), findsWidgets);
    expect(find.text('On-Peak'), findsOneWidget);
    expect(find.text('Off-Peak'), findsOneWidget);
  });

  testWidgets('น้ำ + bangkok -> ใช้ MWA (การประปานครหลวง)', (tester) async {
    await tester.pumpWidget(wrap(const BillMockupCard(
      isElectricity: false,
      area: 'bangkok',
    )));

    expect(find.textContaining('MWA'), findsWidgets);
    expect(find.textContaining('การประปานครหลวง'), findsOneWidget);
  });

  testWidgets('น้ำ + province -> ใช้ PWA (การประปาส่วนภูมิภาค)', (tester) async {
    await tester.pumpWidget(wrap(const BillMockupCard(
      isElectricity: false,
      area: 'province',
    )));

    expect(find.textContaining('PWA'), findsWidgets);
    expect(find.textContaining('การประปาส่วนภูมิภาค'), findsOneWidget);
  });

  testWidgets('isTou ไม่มีผลกับฝั่งน้ำ (น้ำไม่มีแนวคิด TOU)', (tester) async {
    await tester.pumpWidget(wrap(const BillMockupCard(
      isElectricity: false,
      area: 'bangkok',
      isTou: true, // ต้องถูกเพิกเฉยฝั่งน้ำ
    )));

    expect(find.text('On-Peak'), findsNothing);
    expect(find.text('Off-Peak'), findsNothing);
  });
}