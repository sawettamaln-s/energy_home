// เทสหน้าวิเคราะห์ (lib/screens/analysis/analysis_screen.dart) ด้วยข้อมูลจำลอง —
// ส่ง AnalysisService/FirestoreService ที่ใช้ FakeFirebaseFirestore และ
// MockFirebaseAuth เข้าไป ตรวจว่าการ์ดคาดการณ์/เปรียบเทียบ/ข้อสังเกตขึ้นตาม
// ข้อมูลที่มี และเลย์เอาต์ไม่ล้นบนจอเล็ก
//
// หน้านี้คำนวณรอบบิลจากเวลาจริง ข้อมูลในเทสจึงสร้างจากรอบบิลของวันนี้
import 'package:energy_home/models/appliance_model.dart';
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/analysis/analysis_screen.dart';
import 'package:energy_home/services/analysis_service.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/utils/forecaster.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'u1';
const _billingDay = 1;

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreService service;
  final cycleStart = EnergyForecaster.getCycleStart(DateTime.now(), _billingDay);

  setUp(() {
    db = FakeFirebaseFirestore();
    service = FirestoreService(firestore: db);
  });

  Future<void> createUser() => service.createUser(UserModel(
        uid: _uid,
        name: 'ทดสอบ',
        email: 'u1@example.com',
        billingDay: _billingDay,
        startElectricityValue: 1000,
        startWaterValue: 100,
        startBillingMonth: cycleStart.month,
        startBillingYear: cycleStart.year,
        startMeterConfigured: true,
        electricityStartConfigured: true,
        waterStartConfigured: true,
      ));

  // บิลย้อนหลัง 14 เดือน (มีเดือนเดียวกันของปีก่อน) ค่าไฟเพิ่มขึ้นแรงในเดือนล่าสุด
  // ให้เกิดเงื่อนไขของข้อสังเกตแบบเทียบเดือนก่อน/ปีก่อน
  Future<void> addBills() async {
    const units = [310, 280, 330, 420, 520, 560, 480, 400, 380, 360, 340, 300, 320, 450];
    for (var i = 0; i < units.length; i++) {
      final d = DateTime(cycleStart.year, cycleStart.month - units.length + i, 1);
      final u = units[i].toDouble();
      await service.saveBill(BillModel(
        id: '${d.year}-${d.month}',
        uid: _uid,
        year: d.year,
        month: d.month,
        electricityUsed: u,
        electricityCost: u * 4.4,
        waterUsed: 20,
        waterCost: 150,
        totalCost: u * 4.4 + 150,
      ));
    }
  }

  Future<void> addCurrentCycleLog() => service.saveElectricityLog(ElectricityLogModel(
        id: 'e1',
        uid: _uid,
        date: cycleStart.add(const Duration(hours: 30)),
        meterValue: 1045,
        usedFromStart: 45,
        usedFromLast: 45,
        cost: 200,
      ));

  Future<void> pumpAnalysis(
    WidgetTester tester, {
    double width = 390,
    double height = 3000,
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, height * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AnalysisScreen(
        analysisService: AnalysisService(firestore: db),
        firestoreService: service,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('มีบิลและบันทึกรอบนี้ -> การ์ดคาดการณ์ครบทั้งรอบนี้/รอบถัดไป และการ์ดเปรียบเทียบ',
      (tester) async {
    await createUser();
    await addBills();
    await addCurrentCycleLog();
    await pumpAnalysis(tester);

    expect(find.text('คาดการณ์ค่าไฟฟ้า'), findsOneWidget);
    expect(find.textContaining('บิลรอบนี้'), findsOneWidget);
    expect(find.textContaining('บิลรอบถัดไป'), findsOneWidget);
    expect(find.textContaining('เหลืออีก'), findsOneWidget);
    expect(find.text('เทียบบิลล่าสุด'), findsOneWidget);
    expect(find.text('เดือนก่อน'), findsOneWidget);
    expect(find.text('ปีก่อน'), findsOneWidget);
    expect(find.text('เฉลี่ย 6 เดือน'), findsOneWidget);
    expect(find.text('ข้อสังเกต'), findsOneWidget);
  });

  testWidgets('ข้อสังเกตไม่ซ้ำกับการ์ดเปรียบเทียบ (ไม่มีข้อเทียบเดือนก่อน/ปีก่อน)', (tester) async {
    await createUser();
    await addBills();
    await pumpAnalysis(tester);

    expect(find.textContaining('เดือนเดียวกันของปีก่อน'), findsNothing);
    expect(find.textContaining('พุ่งขึ้นจากเดือนก่อน'), findsNothing);
  });

  testWidgets('ยังไม่มีบิลและยังไม่บันทึกรอบนี้ -> การ์ดคาดการณ์บอกวิธีให้มีข้อมูล ไม่มีการ์ดเปรียบเทียบ',
      (tester) async {
    await createUser();
    await pumpAnalysis(tester);

    expect(find.textContaining('บันทึกมิเตอร์ในรอบนี้อย่างน้อย 1 ครั้ง'), findsOneWidget);
    expect(find.textContaining('เพิ่มบิลย้อนหลังที่หน้าตั้งค่า เพื่อให้ระบบคาดการณ์'), findsOneWidget);
    expect(find.text('เทียบบิลล่าสุด'), findsNothing);
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> ทุกแท็บไม่ล้น', (tester) async {
    await createUser();
    await addBills();
    await addCurrentCycleLog();
    await service.saveAppliance(ApplianceModel(
      id: 'a1',
      uid: _uid,
      name: 'เครื่องปรับอากาศห้องนอนใหญ่ชั้นสอง',
      watt: 1200,
      schedules: [ScheduleModel(days: const [0, 1, 2, 3, 4, 5, 6], startTime: '00:00', endTime: '08:00')],
    ));
    await pumpAnalysis(tester, width: 320, textScale: 1.3);
    expect(tester.takeException(), isNull);

    // สลับกราฟไปมุมมองหน่วย
    await tester.tap(find.text('หน่วย').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final tab in ['น้ำ', 'อุปกรณ์']) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('อุปกรณ์ที่ใช้ไฟ'), findsOneWidget);
  });
}
