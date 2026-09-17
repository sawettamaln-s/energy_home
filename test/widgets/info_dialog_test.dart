// เทส showInfoDialog (lib/widgets/info_dialog.dart) — dialog "info + หัวข้อ +
// เนื้อหา + ปุ่มเข้าใจแล้ว" ที่ใช้ซ้ำทั่วแอป รองรับทั้งเนื้อหาแบบข้อความล้วน
// (message) และเนื้อหากำหนดเอง (contentBuilder)
//
// ครอบ:
//   1) โหมด message: แสดง title/message/ปุ่ม default ("เข้าใจแล้ว") ถูกต้อง
//      และกดปุ่มแล้วปิด dialog ได้
//   2) โหมด contentBuilder: render widget ที่ส่งเข้าไปได้จริง แทนที่จะ
//      พยายามอ่าน message (ซึ่งเป็น null ในเคสนี้)
//   3) buttonLabel แบบกำหนดเอง
import 'package:energy_home/widgets/info_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('โหมด message: แสดง title/message/ปุ่ม default', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showInfoDialog(
              context,
              title: 'คำนวณอย่างไร?',
              message: 'ใช้ค่าเฉลี่ยการใช้งานย้อนหลัง',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('คำนวณอย่างไร?'), findsOneWidget);
    expect(find.text('ใช้ค่าเฉลี่ยการใช้งานย้อนหลัง'), findsOneWidget);
    expect(find.text('เข้าใจแล้ว'), findsOneWidget);

    await tester.tap(find.text('เข้าใจแล้ว'));
    await tester.pumpAndSettle();

    expect(find.text('คำนวณอย่างไร?'), findsNothing);
  });

  testWidgets('โหมด contentBuilder: render widget ที่ส่งเข้าไปได้จริง',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showInfoDialog(
              context,
              title: 'รายละเอียดเพิ่มเติม',
              contentBuilder: (_) => const Text('เนื้อหากำหนดเอง'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('เนื้อหากำหนดเอง'), findsOneWidget);
  });

  testWidgets('buttonLabel แบบกำหนดเอง', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showInfoDialog(
              context,
              title: 'แจ้งเตือน',
              message: 'ok',
              buttonLabel: 'รับทราบ',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('รับทราบ'), findsOneWidget);
    expect(find.text('เข้าใจแล้ว'), findsNothing);
  });

  testWidgets(
      'showApplianceEstimateInfoDialog แสดงคำอธิบายสูตรคำนวณและคำเตือนคอมเพรสเซอร์',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showApplianceEstimateInfoDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ตัวเลขนี้คำนวณอย่างไร?'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}