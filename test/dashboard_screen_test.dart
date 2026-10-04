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

  Future<void> pumpDashboard(WidgetTester tester, {bool signedIn = true}) async {
    await tester.pumpWidget(MaterialApp(
      home: DashboardScreen(
        loader: DashboardLoader(firestoreService: service),
        auth: MockFirebaseAuth(
            signedIn: signedIn, mockUser: MockUser(uid: _uid)),
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

    expect(find.textContaining('ประมาณการบิล'), findsOneWidget);
    // ค่าไฟที่ใช้ไปแล้ว และรวมถึงตอนนี้ (ยังไม่มีรายจ่ายประจำ) เป็นยอดเดียวกัน
    expect(find.text('250.00 บาท'), findsNWidgets(2));
    expect(find.text('รวมถึงตอนนี้'), findsOneWidget);
    expect(find.textContaining('คาดว่าบิลทั้งรอบ'), findsOneWidget);
    expect(find.text('บันทึกมิเตอร์'), findsNWidgets(2));
  });

  testWidgets('เลขต้นรอบเป็นของรอบก่อน -> การ์ดล็อกให้ตั้งรอบใหม่',
      (tester) async {
    await createUser(configured: true, startMonth: prevCycleStart);
    await pumpDashboard(tester);

    expect(find.textContaining('รอบบิลใหม่เริ่ม'), findsNWidgets(2));
    expect(find.text('ตั้งรอบใหม่'), findsNWidgets(2));
  });

  testWidgets('ยังไม่ได้เข้าสู่ระบบ/โหลดไม่สำเร็จ -> หน้าลองใหม่', (tester) async {
    await pumpDashboard(tester, signedIn: false);

    expect(find.text('โหลดข้อมูลไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);
  });
}
