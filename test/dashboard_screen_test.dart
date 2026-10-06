// เทสหน้าหลัก (lib/screens/dashboard/dashboard_screen.dart) ด้วยข้อมูลจำลอง —
// ส่ง DashboardLoader ที่ใช้ FakeFirebaseFirestore และ MockFirebaseAuth เข้าไป
// ตรวจว่าการ์ดที่ขึ้นตรงกับสถานะบัญชี: ผู้ใช้ใหม่ / พร้อมบันทึก / เลขต้นรอบ
// เป็นของรอบก่อน / โหลดไม่สำเร็จ
//
// หน้านี้คำนวณรอบบิลจากเวลาจริง ข้อมูลในเทสจึงสร้างจากรอบบิลของวันนี้
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/dashboard/dashboard_loader.dart';
import 'package:energy_home/screens/dashboard/dashboard_screen.dart';
import 'package:energy_home/screens/dashboard/widgets/meter_cards.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/services/notification_service.dart';
import 'package:energy_home/utils/forecaster.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'u1';
const _billingDay = 1;

void main() {
  late FirestoreService service;
  final cycleStart = EnergyForecaster.getCycleStart(DateTime.now(), _billingDay);
  final prevCycleStart =
      EnergyForecaster.getPreviousCycleStart(cycleStart, _billingDay);

  setUp(() {
    // ข้ามคู่มือเริ่มต้นใช้งาน (popup ครั้งแรก)
    SharedPreferences.setMockInitialValues({'has_seen_onboarding_guide': true});
    NotificationService.instance.uidProvider = () => _uid;
    service = FirestoreService(firestore: FakeFirebaseFirestore());
  });

  Future<void> createUser({required bool configured, DateTime? startMonth}) {
    final start = startMonth ?? cycleStart;
    return service.createUser(UserModel(
      uid: _uid,
      name: 'ทดสอบ',
      email: 'u1@example.com',
      billingDay: _billingDay,
      startElectricityValue: 1000,
      startWaterValue: 100,
      startBillingMonth: configured ? start.month : 0,
      startBillingYear: configured ? start.year : 0,
      startMeterConfigured: configured,
      electricityStartConfigured: configured,
      waterStartConfigured: configured,
    ));
  }

  // ขนาดจอมือถือ (กว้าง 390) ค่าเริ่มต้น — [width]/[textScale] ใช้ลองจอเล็ก
  // ตัวอักษรใหญ่ ถ้าเลย์เอาต์ล้น เทสจะล้มเอง
  Future<void> pumpDashboard(
    WidgetTester tester, {
    bool signedIn = true,
    double width = 390,
    double textScale = 1.0,
    ValueChanged<int>? onNavTap,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 844 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(textScale)),
        child: DashboardScreen(
          loader: DashboardLoader(firestoreService: service),
          auth: MockFirebaseAuth(
              signedIn: signedIn, mockUser: MockUser(uid: _uid)),
          onNavTap: onNavTap,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('ผู้ใช้ใหม่ยังไม่ตั้งเลขต้นรอบ -> การ์ดเช็คลิสต์ 3 ขั้นตอน',
      (tester) async {
    await createUser(configured: false);
    await pumpDashboard(tester);

    expect(find.text('เริ่มต้นใช้งาน 3 ขั้นตอน'), findsOneWidget);
    expect(find.text('บันทึกมิเตอร์'), findsNothing);
  });

  testWidgets('ตั้งเลขต้นรอบของรอบนี้แล้ว -> การ์ดบันทึกมิเตอร์ทั้งไฟและน้ำ',
      (tester) async {
    await createUser(configured: true);
    await service.saveElectricityLog(ElectricityLogModel(
        id: 'e1', uid: _uid, date: cycleStart.add(const Duration(hours: 30)),
        meterValue: 1050, usedFromStart: 50, cost: 250));
    await pumpDashboard(tester);

    expect(find.textContaining(RegExp(r'^เหลือ \d+ วัน$')), findsOneWidget);
    // ตัวเลขหลักเป็นยอดที่ใช้ไปแล้ว การ์ดไฟฟ้าบอกค่าไฟ หน่วยที่ใช้ และวันที่จด
    expect(find.text('ใช้ไปแล้วรอบนี้'), findsOneWidget);
    expect(find.text('ค่าไฟ + ค่าน้ำ'), findsOneWidget);
    expect(find.text('ใช้ 50 หน่วย'), findsOneWidget);
    expect(find.text('รอบนี้ยังไม่ได้จด'), findsOneWidget); // ฝั่งน้ำ
    // ยอดใช้ไปแล้ว (การ์ดเด่น) กับค่าไฟในการ์ดไฟฟ้า (ยังไม่มีรายจ่ายประจำ)
    // เป็นยอดเดียวกัน
    expect(find.text('250.00 บาท'), findsNWidgets(2));
    // หน้าหลักแสดงแต่ยอดจริง ไม่แสดงยอดคาดการณ์สิ้นรอบ
    expect(find.textContaining('สิ้นรอบบิลน่าจะ'), findsNothing);
    expect(find.text('บันทึกมิเตอร์'), findsNWidgets(2));
  });

  testWidgets('เลขต้นรอบเป็นของรอบก่อน -> การ์ดล็อกให้ตั้งรอบใหม่',
      (tester) async {
    await createUser(configured: true, startMonth: prevCycleStart);
    await pumpDashboard(tester);

    expect(find.textContaining('รอบบิลใหม่เริ่ม'), findsNWidgets(2));
    expect(find.text('ตั้งรอบใหม่'), findsNWidgets(2));
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> ไม่ล้น',
      (tester) async {
    await createUser(configured: true);
    await service.saveElectricityLog(ElectricityLogModel(
        id: 'e1', uid: _uid, date: cycleStart.add(const Duration(hours: 30)),
        meterValue: 12345.5, usedFromStart: 950, cost: 4321.25));
    await pumpDashboard(tester, width: 320, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('บันทึกมิเตอร์'), findsNWidgets(2));
  });

  testWidgets('ผู้ใช้ใหม่ จอเล็ก ตัวอักษรใหญ่ -> การ์ดเช็คลิสต์ไม่ล้น',
      (tester) async {
    await createUser(configured: false);
    await pumpDashboard(tester, width: 320, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('เริ่มต้นใช้งาน 3 ขั้นตอน'), findsOneWidget);
  });

  testWidgets('ยังไม่ได้เข้าสู่ระบบ/โหลดไม่สำเร็จ -> หน้าลองใหม่', (tester) async {
    await pumpDashboard(tester, signedIn: false);

    expect(find.text('โหลดข้อมูลไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);
  });

  testWidgets('ชิปดูคาดการณ์ -> สลับไปแท็บวิเคราะห์', (tester) async {
    await createUser(configured: true);
    final tapped = <int>[];
    await pumpDashboard(tester, onNavTap: tapped.add);

    await tester.tap(find.text('ดูคาดการณ์'));
    expect(tapped, [1]);
  });

  test('ข้อความจดล่าสุด: นับวันตามปฏิทิน ไม่สนเวลา', () {
    final now = DateTime(2026, 10, 4, 8);
    expect(MeterSummaryCard.lastRecordedText(null, now), 'รอบนี้ยังไม่ได้จด');
    expect(MeterSummaryCard.lastRecordedText(DateTime(2026, 10, 4, 1), now),
        'จดล่าสุด วันนี้');
    expect(MeterSummaryCard.lastRecordedText(DateTime(2026, 10, 3, 23), now),
        'จดล่าสุด เมื่อวาน');
    expect(MeterSummaryCard.lastRecordedText(DateTime(2026, 9, 30, 9), now),
        'จดล่าสุด 4 วันก่อน');
  });
}
