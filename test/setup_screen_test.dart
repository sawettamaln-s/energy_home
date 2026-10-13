// เทสหน้าตั้งค่าเริ่มต้น (lib/screens/auth/setup_screen.dart) — ตัวเลือกมิเตอร์ปกติ
// บอกประเภทอัตราตั้งต้นด้วยรหัสของการไฟฟ้าในพื้นที่ที่เลือกในขั้นแรก
import 'package:energy_home/screens/auth/setup_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSetup(WidgetTester tester, {double width = 390, double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SetupScreen(firestoreService: FirestoreService(firestore: FakeFirebaseFirestore())),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> goToMeterStep(WidgetTester tester) async {
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
  }

  testWidgets('กรุงเทพฯ -> มิเตอร์ปกติตั้งต้นที่ประเภท 1.2 แก้ได้ที่ตั้งค่า', (tester) async {
    await pumpSetup(tester);
    await goToMeterStep(tester);

    expect(find.textContaining('ตั้งต้นที่ประเภท 1.2 (ใช้เกิน 150 หน่วย/เดือน)'), findsOneWidget);
    expect(find.textContaining('แก้ได้ภายหลังที่ ตั้งค่า > ประเภทอัตราค่าไฟ'), findsOneWidget);
  });

  testWidgets('ส่วนภูมิภาค -> ใช้รหัสของ กฟภ. (1.1.2)', (tester) async {
    await pumpSetup(tester);
    await tester.tap(find.text('ส่วนภูมิภาค'));
    await tester.pumpAndSettle();
    await goToMeterStep(tester);

    expect(find.textContaining('ตั้งต้นที่ประเภท 1.1.2'), findsOneWidget);
  });

  testWidgets('ปุ่มอธิบายประเภทมิเตอร์ -> บอกวิธีดูขนาดมิเตอร์จากหน้าปัด 5(15)A / 15(45)A', (tester) async {
    await pumpSetup(tester);
    await goToMeterStep(tester);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('5(15)A = 5 แอมแปร์'), findsOneWidget);
    expect(find.textContaining('15(45)A หรือใหญ่กว่า'), findsOneWidget);
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> ขั้นเลือกมิเตอร์ไม่ล้น', (tester) async {
    await pumpSetup(tester, width: 320, textScale: 1.3);
    await goToMeterStep(tester);
    expect(tester.takeException(), isNull);
  });
}
