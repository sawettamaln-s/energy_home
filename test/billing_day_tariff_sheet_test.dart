// เทสแผ่นเลือกวันตัดรอบบิล (settings_billing_day.dart) และแผ่นเลือกประเภท
// อัตราค่าไฟ (settings_tariff.dart) เปิดผ่านแถวเมนูในหน้าตั้งค่า
//
// ครอบ: ตัวอย่างรอบบิลใต้ตารางวันตรงกับ EnergyForecaster, บันทึกวันแล้วค่าใน
// เอกสารผู้ใช้เปลี่ยน, เลือกประเภทอัตราแล้วบันทึก, ไม่เปลี่ยนอะไรปุ่มเป็น "ปิด"
// และเลย์เอาต์ไม่ล้นบนจอเล็ก
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/settings/settings_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/services/notification_service.dart';
import 'package:energy_home/utils/calculator.dart';
import 'package:energy_home/utils/forecaster.dart';
import 'package:energy_home/utils/thai_date_utils.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'u1';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NotificationService.instance.uidProvider = () => _uid;
    db = FakeFirebaseFirestore();
    service = FirestoreService(firestore: db);
    await service.createUser(UserModel(
      uid: _uid,
      name: 'ทดสอบ',
      email: 'u1@example.com',
      billingDay: 15,
      billingDayConfigured: true,
    ));
  });

  Future<Map<String, dynamic>> userDoc() async => (await db.collection('users').doc(_uid).get()).data()!;

  String short(DateTime d) => '${d.day} ${thaiMonthsShort[d.month - 1]} ${(d.year + 543) % 100}';

  Future<void> open(WidgetTester tester, String menu, {double width = 390, double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 2400 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SettingsScreen(
        firestoreService: service,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid)),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(menu).first);
    await tester.pumpAndSettle();
  }

  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

  testWidgets('วันตัดรอบ: แตะวันแล้วตัวอย่างรอบบิลเปลี่ยนตาม และบันทึกได้', (tester) async {
    await open(tester, 'วันตัดรอบบิล');
    expect(find.text('ตัดรอบทุกวันที่ 15 ของเดือน'), findsOneWidget);

    await tester.tap(inSheet(find.text('5')));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final start = EnergyForecaster.getCycleStart(now, 5);
    final end = EnergyForecaster.getCycleEnd(now, 5).subtract(const Duration(days: 1));
    expect(find.text('ตัดรอบทุกวันที่ 5 ของเดือน'), findsOneWidget);
    expect(find.text('${short(start)} – ${short(end)}'), findsOneWidget);

    await tester.tap(inSheet(find.text('บันทึก')));
    await tester.pumpAndSettle();
    expect((await userDoc())['billingDay'], 5);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('วันตัดรอบ: เลือกวันที่ 31 -> บอกกติกาเดือนที่มีไม่ถึง 31 วัน', (tester) async {
    await open(tester, 'วันตัดรอบบิล');
    await tester.tap(inSheet(find.text('31')));
    await tester.pumpAndSettle();

    expect(find.textContaining('เดือนที่มีไม่ถึง 31 วัน'), findsOneWidget);
  });

  testWidgets('ประเภทอัตรา: เลือกประเภทไม่เกิน 150 หน่วยแล้วบันทึก', (tester) async {
    await open(tester, 'ประเภทอัตราค่าไฟ');
    // ยังไม่เปลี่ยน ปุ่มเป็น "ปิด"
    expect(inSheet(find.text('ปิด')), findsOneWidget);
    expect(find.text('ใช้อยู่'), findsOneWidget);

    await tester.tap(find.text('ใช้ไม่เกิน 150 หน่วย/เดือน'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('บันทึก')));
    await tester.pumpAndSettle();

    expect((await userDoc())['electricityTariff'], EnergyCalculator.tariffSmall);
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> ทั้งสองแผ่นไม่ล้น', (tester) async {
    await open(tester, 'วันตัดรอบบิล', width: 320, textScale: 1.3);
    await tester.tap(inSheet(find.text('30')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('จอเล็ก: แผ่นประเภทอัตราไม่ล้น', (tester) async {
    await open(tester, 'ประเภทอัตราค่าไฟ', width: 320, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
