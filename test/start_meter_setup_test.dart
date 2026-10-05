// เทสหน้าตั้งเลขมิเตอร์ต้นรอบ (lib/screens/settings/settings_start_meter.dart)
// เปิดผ่าน openStartMeterSetup() ตัวเดียวกับที่แดชบอร์ด/หน้าบันทึกมิเตอร์ใช้
//
// ครอบ 3 ส่วน:
//   1) หน้าประวัติ — รายการว่าง, ซ่อนปุ่ม (+) เมื่อรอบปัจจุบันตั้งครบแล้ว,
//      ลบข้อมูลฝั่งเดียวของแถวรอบปัจจุบัน
//   2) ฟอร์มตั้งค่าใหม่ — ครั้งแรกสุด (ต้องกรอกหน่วยที่ใช้), รอบถัดไป (คำนวณ
//      หน่วยจาก delta รอบก่อน), กรอกไม่ครบ, ยังไม่มีบิล, เลขต่ำกว่ารอบก่อน
//      (เตือน + ถามยืนยัน ไม่บล็อก เพราะอาจเปลี่ยนมิเตอร์ใหม่จริง), TOU, น้ำอย่างเดียว
//   3) แก้ไขรอบปัจจุบัน — แก้เลขต้นรอบแล้ว log ในรอบถูกคำนวณใหม่, ล้างเลขต้นรอบ
//
// ใช้ FakeFirebaseFirestore แทนของจริง — เดือนของรอบบิลคำนวณจาก
// DateTime.now() ด้วย EnergyForecaster ตัวเดียวกับแอป เทสจึงไม่ผูกกับวันที่รัน
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/start_meter_record_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/settings/settings_screen.dart'
    show openStartMeterSetup;
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/utils/forecaster.dart';
import 'package:energy_home/utils/thai_date_utils.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'user-1';
const _billingDay = 30;

void main() {
  late FakeFirebaseFirestore fakeDb;
  late FirestoreService service;

  // รอบบิลปัจจุบัน (เดือนที่ฟอร์มจะตั้งค่าให้) และรอบก่อนหน้า
  final cycle = EnergyForecaster.getCycleStart(DateTime.now(), _billingDay);
  final prevCycle = EnergyForecaster.getPreviousCycleStart(cycle, _billingDay);
  String monthLabel(DateTime d) => '${thaiMonths[d.month - 1]} ${d.year + 543}';

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    service = FirestoreService(firestore: fakeDb);
  });

  DocumentReference<Map<String, dynamic>> userDoc() =>
      fakeDb.collection('users').doc(_uid);

  Future<void> seedUser({
    String meterType = 'normal',
    bool configuredForCurrentCycle = false,
    bool electricityConfigured = false,
    bool waterConfigured = false,
    double startElectricity = 0,
    double startWater = 0,
  }) =>
      userDoc().set(UserModel(
        uid: _uid,
        name: 'Test',
        email: 'test@example.com',
        meterType: meterType,
        billingDay: _billingDay,
        startElectricityValue: startElectricity,
        startWaterValue: startWater,
        startBillingMonth: configuredForCurrentCycle ? cycle.month : 0,
        startBillingYear: configuredForCurrentCycle ? cycle.year : 0,
        startMeterConfigured: configuredForCurrentCycle,
        electricityStartConfigured: electricityConfigured,
        waterStartConfigured: waterConfigured,
      ).toMap());

  Future<void> seedRecord(
    String id,
    DateTime month, {
    double electricity = 0,
    double water = 0,
    double peak = 0,
    double offPeak = 0,
  }) =>
      userDoc().collection('start_meter_history').doc(id).set(
            StartMeterRecordModel(
              id: id,
              uid: _uid,
              electricityValue: electricity,
              waterValue: water,
              peakValue: peak,
              offPeakValue: offPeak,
              billingMonth: month.month,
              billingYear: month.year,
              recordedAt: month,
            ).toMap(),
          );

  Future<Map<String, dynamic>> userData() async => (await userDoc().get()).data()!;

  Future<List<Map<String, dynamic>>> docs(String collection) async =>
      (await userDoc().collection(collection).get())
          .docs
          .map((d) => d.data())
          .toList();

  Future<void> openSetup(WidgetTester tester, {bool isTou = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => openStartMeterSetup(context, _uid, service, isTou),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  // ช่องกรอกในฟอร์มอยู่ใน Column เดียวกับ label ของตัวเอง
  Finder fieldFor(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
        matching: find.byType(TextField),
      );

  // พิมพ์แล้วรอ debounce คำนวณค่าใช้จ่ายอัตโนมัติ (400ms) ให้เสร็จ
  Future<void> enter(WidgetTester tester, String label, String text) async {
    final field = fieldFor(label);
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  const meterLabel = 'เลขอ่านครั้งหลัง (last meter reading)';
  const usedLabel = 'จำนวนหน่วย (kWh)';
  const costLabel = 'ค่าใช้จ่าย';
  const generalError = 'กรอกให้ครบอย่างน้อย 1 ประเภท (ไฟฟ้า หรือ น้ำ) ก่อนถึงจะบันทึกได้';

  group('หน้าประวัติ', () {
    testWidgets('ยังไม่มีประวัติ -> โชว์ข้อความว่าง และมีปุ่ม (+)', (tester) async {
      await seedUser();
      await openSetup(tester);

      expect(find.text('ยังไม่มีประวัติการตั้งเลขมิเตอร์ต้นรอบ'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('รอบปัจจุบันตั้งครบแล้ว -> ซ่อนปุ่ม (+) และโชว์แถวของรอบนี้',
        (tester) async {
      await seedUser(
          configuredForCurrentCycle: true,
          electricityConfigured: true,
          startElectricity: 5000);
      await seedRecord('r-current', cycle, electricity: 5000);
      await openSetup(tester);

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text(monthLabel(cycle)), findsWidgets);
    });

    testWidgets('ลบฝั่งไฟฟ้าของรอบปัจจุบันที่มีน้ำด้วย -> เก็บน้ำไว้ รีเซ็ตเฉพาะไฟฟ้า',
        (tester) async {
      await seedUser(
          configuredForCurrentCycle: true,
          electricityConfigured: true,
          waterConfigured: true,
          startElectricity: 5000,
          startWater: 300);
      await seedRecord('r-current', cycle, electricity: 5000, water: 300);
      await openSetup(tester);

      await tapText(tester, monthLabel(cycle));
      await tapText(tester, 'ลบข้อมูลไฟฟ้า');
      expect(find.text('ลบข้อมูลไฟฟ้ารายการนี้?'), findsOneWidget);
      await tapText(tester, 'ลบ');

      final records = await docs('start_meter_history');
      expect(records, hasLength(1));
      expect(records.single['electricityValue'], 0);
      expect(records.single['waterValue'], 300);

      final user = await userData();
      expect(user['startElectricityValue'], 0);
      expect(user['electricityStartConfigured'], isFalse);
      expect(user['waterStartConfigured'], isTrue);
      expect(user['startMeterConfigured'], isTrue,
          reason: 'น้ำยังตั้งค่าอยู่ ถือว่ายังตั้งค่าต้นรอบแล้วในความหมายรวม');
    });

    testWidgets('ลบฝั่งเดียวที่เหลืออยู่ของรอบปัจจุบัน -> ลบทั้งแถว และถือว่ายังไม่ได้ตั้งค่า',
        (tester) async {
      await seedUser(
          configuredForCurrentCycle: true,
          electricityConfigured: true,
          startElectricity: 5000);
      await seedRecord('r-current', cycle, electricity: 5000);
      await openSetup(tester);

      await tapText(tester, monthLabel(cycle));
      await tapText(tester, 'ลบข้อมูลไฟฟ้า');
      await tapText(tester, 'ลบ');

      expect(await docs('start_meter_history'), isEmpty);
      final user = await userData();
      expect(user['electricityStartConfigured'], isFalse);
      expect(user['startMeterConfigured'], isFalse);
      expect(user['startBillingMonth'], 0);
      // ไม่มีรอบปัจจุบันแล้ว ปุ่ม (+) ต้องกลับมา
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('ฟอร์มตั้งค่าต้นรอบใหม่', () {
    testWidgets('ครั้งแรกสุด: กรอกเลข + หน่วยที่ใช้ + ค่าใช้จ่าย -> บันทึกครบทั้ง user/ประวัติ/บิล',
        (tester) async {
      await seedUser();
      await openSetup(tester);
      await openSheet(tester);

      expect(find.text(monthLabel(cycle)), findsOneWidget);
      expect(find.text('ตั้งใหม่'), findsOneWidget);

      await enter(tester, meterLabel, '5000');
      await enter(tester, usedLabel, '300');
      await enter(tester, costLabel, '1200');
      await tapText(tester, 'บันทึก');

      final user = await userData();
      expect(user['startElectricityValue'], 5000);
      expect(user['electricityStartConfigured'], isTrue);
      expect(user['startMeterConfigured'], isTrue);
      expect(user['startBillingMonth'], cycle.month);
      expect(user['startBillingYear'], cycle.year);

      final records = await docs('start_meter_history');
      expect(records.single['electricityValue'], 5000);

      final bills = await docs('bills');
      expect(bills.single['electricityUsed'], 300);
      expect(bills.single['electricityCost'], 1200);
      expect(bills.single['source'], 'startMeter');

      // ปิด sheet แล้วหน้าประวัติโหลดใหม่ เห็นแถวของรอบนี้
      expect(find.text('ยังไม่มีประวัติการตั้งเลขมิเตอร์ต้นรอบ'), findsNothing);
    });

    testWidgets('กรอกเลขมิเตอร์อย่างเดียว ไม่มีค่าใช้จ่าย -> ขึ้น "กรอกไม่ครบ" และบันทึกไม่ได้',
        (tester) async {
      await seedUser();
      await seedRecord('r-prev', prevCycle, electricity: 5000);
      await openSetup(tester);
      await openSheet(tester);

      await enter(tester, meterLabel, '5300');
      await tester.enterText(fieldFor(costLabel), '');
      await tester.pumpAndSettle();
      expect(find.text('กรอกไม่ครบ'), findsOneWidget);

      await tapText(tester, 'บันทึก');
      expect(find.text(generalError), findsOneWidget);
      expect(await docs('bills'), isEmpty);
      expect(await docs('start_meter_history'), hasLength(1));
    });

    testWidgets('รอบถัดไป: คำนวณหน่วยจาก delta รอบก่อน + เติมค่าใช้จ่ายให้อัตโนมัติ',
        (tester) async {
      await seedUser();
      await seedRecord('r-prev', prevCycle, electricity: 5000);
      await openSetup(tester);
      await openSheet(tester);

      // รอบถัดไปไม่ต้องกรอกหน่วยที่ใช้เอง
      expect(find.text(usedLabel), findsNothing);

      await enter(tester, meterLabel, '5300');
      expect(find.textContaining('ใช้ไป 300 หน่วย'), findsOneWidget);

      final autoCost = tester.widget<TextField>(fieldFor(costLabel)).controller!.text;
      expect(double.parse(autoCost), greaterThan(0));

      await tapText(tester, 'บันทึก');
      final bills = await docs('bills');
      expect(bills.single['electricityUsed'], 300);
      expect(bills.single['electricityCost'], double.parse(autoCost));
    });

    testWidgets('ติ๊ก "ยังไม่มีบิล" -> กรอกแค่เลขมิเตอร์ก็บันทึกได้ ค่าใช้จ่ายเป็น 0',
        (tester) async {
      await seedUser();
      await seedRecord('r-prev', prevCycle, electricity: 5000);
      await openSetup(tester);
      await openSheet(tester);

      await enter(tester, meterLabel, '5300');
      await tapText(tester,
          'ยังไม่มีบิลไฟฟ้าตอนนี้ (มีแต่เลขมิเตอร์ที่อ่านจากหน้าปัดเอง)');
      await tapText(tester, 'บันทึก');

      expect((await userData())['startElectricityValue'], 5300);
      final bills = await docs('bills');
      expect(bills.single['electricityCost'], 0);
      expect(bills.single['electricityUsed'], 300);
    });

    testWidgets('เลขต่ำกว่ารอบก่อน -> เตือน + ถามยืนยัน ยกเลิกแล้วไม่บันทึก ยืนยันแล้วบันทึก',
        (tester) async {
      await seedUser();
      await seedRecord('r-prev', prevCycle, electricity: 5000);
      await openSetup(tester);
      await openSheet(tester);

      await enter(tester, meterLabel, '4900');
      await enter(tester, costLabel, '500');
      expect(find.textContaining('เลขมิเตอร์ไฟฟ้าที่กรอกต่ำกว่ารอบก่อนหน้า'),
          findsOneWidget);

      await tapText(tester, 'บันทึก');
      expect(find.text('เลขมิเตอร์ต่ำกว่ารอบก่อนหน้า'), findsOneWidget);
      // เป็นการยืนยันบันทึก ไม่ใช่ลบ — ปุ่มต้องไม่ใช้คำว่า "ลบ"
      expect(find.text('ลบ'), findsNothing);
      await tapText(tester, 'กลับไปแก้ไข');
      expect(await docs('bills'), isEmpty);
      expect((await userData())['startElectricityValue'], 0);

      await tapText(tester, 'บันทึก');
      await tapText(tester, 'บันทึกต่อ');

      expect((await userData())['startElectricityValue'], 4900);
      final bills = await docs('bills');
      expect(bills.single['electricityUsed'], 0,
          reason: 'หน่วยที่ใช้ห้ามติดลบ (calculateUsed คืน 0)');
    });

    testWidgets('ตั้งเฉพาะน้ำ -> ไม่เขียนทับค่าฝั่งไฟฟ้า', (tester) async {
      await seedUser();
      await openSetup(tester);
      await openSheet(tester);

      await tapText(tester, 'น้ำ');
      await enter(tester, 'เลขในมาตร (Current reading)', '300');
      await enter(tester, 'จำนวนน้ำใช้ (Consumption)', '25');
      await enter(tester, costLabel, '250');
      await tapText(tester, 'บันทึก');

      final user = await userData();
      expect(user['startWaterValue'], 300);
      expect(user['waterStartConfigured'], isTrue);
      expect(user['electricityStartConfigured'], isFalse);
      expect(user['startElectricityValue'], 0);

      final bills = await docs('bills');
      expect(bills.single['waterUsed'], 25);
      expect(bills.single['electricityCost'], 0);
    });

    testWidgets('TOU ครั้งแรกสุด: บันทึกเลข On/Off-Peak และหน่วยที่ใช้แยกช่วง',
        (tester) async {
      await seedUser(meterType: 'tou');
      await openSetup(tester, isTou: true);
      await openSheet(tester);

      await enter(tester, 'เลขอ่านครั้งหลัง On-Peak', '1000');
      await enter(tester, 'เลขอ่านครั้งหลัง Off-Peak', '2000');
      await enter(tester, 'On-Peak', '120');
      await enter(tester, 'Off-Peak', '180');
      expect(find.textContaining('รวมหน่วยที่ใช้ :  300 หน่วย'), findsOneWidget);
      await enter(tester, costLabel, '1500');
      await tapText(tester, 'บันทึก');

      final user = await userData();
      expect(user['startPeakValue'], 1000);
      expect(user['startOffPeakValue'], 2000);

      final bills = await docs('bills');
      expect(bills.single['electricityPeakUsed'], 120);
      expect(bills.single['electricityOffPeakUsed'], 180);
      expect(bills.single['electricityUsed'], 300);
    });
  });

  group('แก้ไขรอบปัจจุบัน', () {
    Future<void> seedCurrentCycle() async {
      await seedUser(
          configuredForCurrentCycle: true,
          electricityConfigured: true,
          startElectricity: 5000);
      await seedRecord('r-current', cycle, electricity: 5000);
      await userDoc().collection('bills').doc('b-current').set({
        'id': 'b-current',
        'uid': _uid,
        'year': cycle.year,
        'month': cycle.month,
        'electricityUsed': 300.0,
        'electricityCost': 1200.0,
        'totalCost': 1200.0,
        'source': 'startMeter',
      });
    }

    testWidgets('แก้เลขต้นรอบ -> แก้ทับ record เดิม และคำนวณ log ในรอบนี้ใหม่',
        (tester) async {
      await seedCurrentCycle();
      final log = ElectricityLogModel(
        id: 'log-1',
        uid: _uid,
        date: DateTime.now(),
        meterValue: 5200,
        usedFromStart: 200,
        usedFromLast: 200,
        cost: 800,
      );
      await userDoc().collection('electricity_logs').doc(log.id).set(log.toMap());

      await openSetup(tester);
      await tapText(tester, monthLabel(cycle));
      await tapText(tester, 'แก้ไขรายการนี้');

      expect(find.text('แก้ไข'), findsOneWidget);
      expect(tester.widget<TextField>(fieldFor(meterLabel)).controller!.text,
          '5000.0');

      await enter(tester, meterLabel, '5100');
      await tapText(tester, 'บันทึก');

      final records = await docs('start_meter_history');
      expect(records, hasLength(1), reason: 'โหมดแก้ไขต้องแก้ทับ ไม่สร้างแถวใหม่');
      expect(records.single['electricityValue'], 5100);

      final logs = await docs('electricity_logs');
      expect(logs.single['usedFromStart'], 100);
    });

    testWidgets('ล้างเลขมิเตอร์ต้นรอบ -> รีเซ็ต user และลบ record/บิลของรอบนี้',
        (tester) async {
      await seedCurrentCycle();
      await openSetup(tester);
      await tapText(tester, monthLabel(cycle));
      await tapText(tester, 'แก้ไขรายการนี้');

      await tapText(tester, 'ล้างเลขมิเตอร์ต้นรอบ');
      expect(find.textContaining('เลขมิเตอร์ต้นรอบทั้งหมดจะถูกล้าง'), findsOneWidget);
      await tapText(tester, 'ลบ');

      final user = await userData();
      expect(user['startElectricityValue'], 0);
      expect(user['startMeterConfigured'], isFalse);
      expect(user['electricityStartConfigured'], isFalse);
      expect(await docs('start_meter_history'), isEmpty);
      expect(await docs('bills'), isEmpty);
    });
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> ประวัติ (TOU) และฟอร์มไม่ล้น',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(320 * 3, 700 * 3);
    addTearDown(tester.view.reset);
    await seedUser(meterType: 'tou');
    await seedRecord('r-prev', prevCycle, peak: 123456, offPeak: 234567, water: 98765);
    await seedRecord('r-old', EnergyForecaster.getPreviousCycleStart(prevCycle, _billingDay),
        peak: 123000, offPeak: 234000);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => openStartMeterSetup(context, _uid, service, true),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await openSheet(tester);
    expect(tester.takeException(), isNull);
  });
}
