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
import 'package:energy_home/utils/thai_date_utils.dart';
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

  testWidgets('ยอดใช้ไปแล้วบอกวันที่จดล่าสุด ไม่ใช่ "ถึงวันนี้" และเตือนเมื่อจดล่าสุดนานกว่า 3 วัน',
      (tester) async {
    await createUser();
    await addBills();
    await addCurrentCycleLog();
    await pumpAnalysis(tester);

    final logDate = cycleStart.add(const Duration(hours: 30));
    expect(find.textContaining('ถึงวันที่จดล่าสุด (${logDate.day} ${thaiMonthsShort[logDate.month - 1]}) ใช้ไปแล้ว'),
        findsOneWidget);
    expect(find.textContaining('ถึงวันนี้'), findsNothing);
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(logDate.year, logDate.month, logDate.day))
        .inDays;
    expect(find.textContaining('คาดจากเลขที่จดเมื่อ $days วันก่อน'), days > 3 ? findsOneWidget : findsNothing);
  });

  testWidgets('คำอธิบายการ์ดคาดการณ์บอกความคลาดเคลื่อนที่วัดได้ของทั้งสองส่วน', (tester) async {
    await createUser();
    await addBills();
    await addCurrentCycleLog();
    await pumpAnalysis(tester);
    // ปุ่มคำอธิบายแรกของหน้า = การ์ดคาดการณ์
    await tester.tap(find.byTooltip('คำอธิบาย').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('คลาดจากจริงเฉลี่ยราว 9%'), findsOneWidget);
    expect(find.textContaining('เฉลี่ยราว 15%'), findsOneWidget);
  });

  testWidgets('การ์ดเทียบบิลแสดงหน่วยต่อวันคู่กับยอดเงิน เฉพาะเมื่อบิลล่าสุดมีหน่วย', (tester) async {
    await createUser();
    await addBills();
    await pumpAnalysis(tester);
    // เดือนก่อน ปีก่อน และเฉลี่ย 6 เดือน มีหน่วยครบทุกแถว
    expect(find.textContaining('ใช้ต่อวัน '), findsNWidgets(3));
  });

  testWidgets('บิลล่าสุดกรอกแค่ยอดเงิน -> ไม่แสดงหน่วยต่อวัน', (tester) async {
    await createUser();
    await addBills();
    final last = DateTime(cycleStart.year, cycleStart.month, 1);
    await service.saveBill(BillModel(
        id: '${last.year}-${last.month}', uid: _uid, year: last.year, month: last.month,
        electricityCost: 1500, totalCost: 1500));
    await pumpAnalysis(tester);
    expect(find.textContaining('ใช้ต่อวัน '), findsNothing);
  });

  testWidgets('บันทึกรอบนี้ห่างจากต้นรอบไม่ถึง 1 วัน -> ยังไม่แสดงยอดทั้งรอบ บอกให้บันทึกอีกครั้ง',
      (tester) async {
    await createUser();
    await addBills();
    await service.saveElectricityLog(ElectricityLogModel(
      id: 'e1',
      uid: _uid,
      date: cycleStart.add(const Duration(hours: 2)),
      meterValue: 1002,
      usedFromStart: 2,
      usedFromLast: 2,
      cost: 40,
    ));
    await pumpAnalysis(tester);

    expect(find.textContaining('บันทึกมิเตอร์อีกครั้งเมื่อเริ่มรอบมาแล้วอย่างน้อย 1 วัน'), findsOneWidget);
    expect(find.textContaining('ทั้งรอบน่าจะใช้ประมาณ'), findsNothing);
    expect(find.textContaining('ต่อวันรอบนี้'), findsNothing);
  });

  testWidgets('การ์ดกราฟแสดง 6 เดือนตามปฏิทิน เดือนที่ไม่มีบิลเป็นช่องว่าง', (tester) async {
    await createUser();
    // บิลล่าสุดคือเดือนก่อนรอบนี้ ขาด 3 เดือนกลางช่วง (ล่าสุด -4 ถึง -2)
    final last = DateTime(cycleStart.year, cycleStart.month - 1, 1);
    for (final back in [5, 1, 0]) {
      final d = DateTime(last.year, last.month - back, 1);
      await service.saveBill(BillModel(
          id: '${d.year}-${d.month}', uid: _uid, year: d.year, month: d.month,
          electricityUsed: 300, electricityCost: 1200, totalCost: 1200));
    }
    await pumpAnalysis(tester);

    // ป้ายของเดือนที่ขาดยังอยู่ในกราฟ แกนเวลาไม่ข้ามเดือน
    final gap = DateTime(last.year, last.month - 3, 1);
    final name = thaiMonthsShort[gap.month - 1];
    final label = gap.month == 1 ? '$name${(gap.year + 543) % 100}' : name;
    expect(find.text(label), findsWidgets);
  });

  testWidgets('หน้าประวัติมุมมองหน่วย ไม่นับบิลที่ไม่ได้กรอกหน่วยในรวม/เฉลี่ย', (tester) async {
    await createUser();
    // ปี 2024 ครบ 12 เดือน ม.ค.-มิ.ย. มีหน่วย 300 ก.ค.-ธ.ค. กรอกแค่ยอดเงิน
    for (var m = 1; m <= 12; m++) {
      await service.saveBill(BillModel(
          id: '2024-$m', uid: _uid, year: 2024, month: m,
          electricityUsed: m <= 6 ? 300 : 0, electricityCost: 1200, totalCost: 1200));
    }
    await pumpAnalysis(tester);
    await tester.tap(find.text('ดูทั้งหมด').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('หน่วย').first);
    await tester.pumpAndSettle();

    expect(find.text('1,800 หน่วย'), findsOneWidget); // รวมทั้งปี
    expect(find.text('300 หน่วย'), findsWidgets); // เฉลี่ย 1,800 ÷ 6 ไม่ใช่ ÷ 12
    expect(find.text('150 หน่วย'), findsNothing);
    expect(find.text('ไม่ได้กรอกหน่วย'), findsNWidgets(6));
  });

  testWidgets('ข้อสังเกตไม่ซ้ำกับการ์ดเปรียบเทียบ (ไม่มีข้อเทียบเดือนก่อน/ปีก่อน)', (tester) async {
    await createUser();
    await addBills();
    await pumpAnalysis(tester);

    expect(find.textContaining('เดือนเดียวกันของปีก่อน'), findsNothing);
    expect(find.textContaining('พุ่งขึ้นจากบิลก่อนหน้า'), findsNothing);
  });

  testWidgets('ยังไม่มีบิลและยังไม่บันทึกรอบนี้ -> การ์ดคาดการณ์บอกวิธีให้มีข้อมูล ไม่มีการ์ดเปรียบเทียบ',
      (tester) async {
    await createUser();
    await pumpAnalysis(tester);

    expect(find.textContaining('บันทึกมิเตอร์ในรอบนี้อย่างน้อย 1 ครั้ง'), findsOneWidget);
    expect(find.textContaining('เพิ่มบิลย้อนหลังที่หน้าตั้งค่า เพื่อให้ระบบคาดการณ์'), findsOneWidget);
    expect(find.text('เทียบบิลล่าสุด'), findsNothing);
  });

  // บิลจากใบแจ้งหนี้ล่าสุดใบเดียว (ผู้ใช้ใหม่ที่ยังไม่เคยจดมิเตอร์)
  Future<void> addStartMeterBill() {
    final d = DateTime(cycleStart.year, cycleStart.month, 1);
    return service.saveBill(BillModel(
      id: 'start',
      uid: _uid,
      year: d.year,
      month: d.month,
      electricityUsed: 320,
      electricityCost: 1400,
      waterUsed: 20,
      waterCost: 150,
      totalCost: 1550,
      source: 'startMeter',
    ));
  }

  testWidgets('มีแค่บิลจากใบแจ้งหนี้ ยังไม่เคยจดมิเตอร์ -> ไม่แสดงคาดการณ์บิลรอบถัดไป บอกให้บันทึกครั้งแรก',
      (tester) async {
    await createUser();
    await addStartMeterBill();
    await pumpAnalysis(tester);

    expect(find.textContaining('บันทึกมิเตอร์ครั้งแรกที่หน้าหลัก'), findsOneWidget);
    expect(find.textContaining('เพิ่มบิลย้อนหลังที่หน้าตั้งค่า'), findsNothing);
    expect(find.textContaining('ประมาณ'), findsNothing);
  });

  testWidgets('จดมิเตอร์ไฟฟ้าแล้ว -> แท็บไฟฟ้าแสดงคาดการณ์บิลรอบถัดไป แท็บน้ำยังรอการจดครั้งแรก',
      (tester) async {
    await createUser();
    await addStartMeterBill();
    await addCurrentCycleLog();
    await pumpAnalysis(tester);

    expect(find.textContaining('บันทึกมิเตอร์ครั้งแรกที่หน้าหลัก'), findsNothing);
    expect(find.text('ประมาณ'), findsNWidgets(2)); // รอบนี้ + รอบถัดไป

    await tester.tap(find.text('น้ำ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('บันทึกมิเตอร์ครั้งแรกที่หน้าหลัก'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(Tab, 'น้ำ'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // เรื่องอุปกรณ์อยู่ที่หน้าอุปกรณ์ หน้าวิเคราะห์มีแค่ไฟฟ้ากับน้ำ
    expect(find.widgetWithText(Tab, 'อุปกรณ์'), findsNothing);
  });
}
