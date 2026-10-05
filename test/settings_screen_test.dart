// เทสหน้าหลักของตั้งค่า (lib/screens/settings/settings_screen.dart) ด้วย
// FakeFirebaseFirestore และ MockFirebaseAuth — ตรวจว่าแถวเมนูแสดงค่าปัจจุบัน
// ตัวย่อชื่อภาษาไทยข้ามสระหน้า สวิตช์ประเภทการแจ้งเตือนซ่อนเมื่อยังไม่ได้รับสิทธิ์
// และเลย์เอาต์ไม่ล้นบนจอเล็ก (ในเทสอ่านสิทธิ์แจ้งเตือนไม่ได้ ถือว่ายังไม่ได้อนุญาต)
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/settings/settings_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/services/notification_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'u1';

void main() {
  late FirestoreService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.instance.uidProvider = () => _uid;
    service = FirestoreService(firestore: FakeFirebaseFirestore());
  });

  Future<void> createUser({bool billingDayConfigured = true, double fixedCost = 350}) =>
      service.createUser(UserModel(
        uid: _uid,
        name: 'สมชาย ใจดี',
        email: 'somchai@example.com',
        billingDay: 15,
        billingDayConfigured: billingDayConfigured,
        fixedCost: fixedCost,
      ));

  Future<void> pumpSettings(WidgetTester tester, {double width = 390, double textScale = 1.0}) async {
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
  }

  testWidgets('แถวเมนูแสดงค่าปัจจุบัน: วันตัดรอบ ประเภทอัตรา รายจ่ายประจำเดือนนี้', (tester) async {
    await createUser();
    await pumpSettings(tester);

    expect(find.text('วันที่ 15'), findsOneWidget);
    expect(find.text('ประเภท 1.2'), findsOneWidget);
    expect(find.text('เดือนนี้ 350 บาท'), findsOneWidget);
  });

  testWidgets('ยังไม่ได้ตั้งวันตัดรอบ / ไม่มีรายจ่ายประจำ -> บอกสถานะแทนตัวเลข', (tester) async {
    await createUser(billingDayConfigured: false, fixedCost: 0);
    await pumpSettings(tester);

    expect(find.text('ยังไม่ได้ตั้ง'), findsOneWidget);
    expect(find.text('ยังไม่มี'), findsOneWidget);
  });

  testWidgets('ตัวย่อชื่อภาษาไทยข้ามสระที่เขียนหน้าพยัญชนะ', (tester) async {
    await createUser();
    await pumpSettings(tester);

    expect(find.text('สจ'), findsOneWidget);
  });

  testWidgets('ยังไม่ได้รับสิทธิ์แจ้งเตือน -> ซ่อนสวิตช์ประเภทย่อย', (tester) async {
    await createUser();
    await pumpSettings(tester);

    expect(find.text('การแจ้งเตือนของแอป'), findsOneWidget);
    expect(find.text('ถึงวันตัดรอบบิล'), findsNothing);
    expect(find.text('สรุปยอดท้ายรอบบิล'), findsNothing);
  });

  testWidgets('กดออกจากระบบ -> ถามยืนยันก่อน', (tester) async {
    await createUser();
    await pumpSettings(tester);

    await tester.tap(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();
    expect(find.text('ต้องการออกจากระบบใช่ไหมคะ?'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> ไม่ล้น', (tester) async {
    await createUser();
    await pumpSettings(tester, width: 320, textScale: 1.3);

    expect(tester.takeException(), isNull);
  });
}
