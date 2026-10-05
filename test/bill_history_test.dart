// เทสหน้าบิลย้อนหลัง (lib/screens/settings/settings_bill_history.dart + ฟอร์ม
// settings_bill_form.dart) ด้วย FakeFirebaseFirestore
//
// ครอบ: การ์ดสรุปบอกเดือนที่ขาด, กติกาตามที่มาของบิล (startMeter ล็อก, compiled
// แก้ได้แต่ลบไม่ได้, imported ลบได้), ฟอร์มกรอกไม่ครบแจ้งในฟอร์มและไม่บันทึก,
// บันทึกบิลใหม่ได้ และเลย์เอาต์ไม่ล้นบนจอเล็ก — รอบบิลคำนวณจากเวลาจริง
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/settings/settings_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/utils/forecaster.dart';
import 'package:energy_home/utils/thai_date_utils.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'u1';
const _billingDay = 1;

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreService service;
  final current = EnergyForecaster.getCycleStart(DateTime.now(), _billingDay);
  // รอบที่ปิดไปแล้ว 1, 2, 3 รอบก่อน
  final m1 = EnergyForecaster.getPreviousCycleStart(current, _billingDay);
  final m2 = EnergyForecaster.getPreviousCycleStart(m1, _billingDay);
  final m3 = EnergyForecaster.getPreviousCycleStart(m2, _billingDay);

  String short(DateTime d) => '${thaiMonthsShort[d.month - 1]} ${(d.year + 543) % 100}';

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = FirestoreService(firestore: db);
    // เริ่มใช้แอปตั้งแต่ m3 — เดือนที่ไม่มีบิลระหว่างนั้นนับเป็นเดือนที่ขาด
    await service.createUser(UserModel(
      uid: _uid,
      name: 'ทดสอบ',
      email: 'u1@example.com',
      billingDay: _billingDay,
      startBillingMonth: m3.month,
      startBillingYear: m3.year,
      startMeterConfigured: true,
    ));
  });

  Future<void> addBill(String id, DateTime month, String source, {double cost = 1000}) => service.saveBill(BillModel(
        id: id,
        uid: _uid,
        year: month.year,
        month: month.month,
        electricityUsed: 250,
        electricityCost: cost,
        totalCost: cost,
        source: source,
      ));

  Future<List<String>> billIds() async =>
      (await db.collection('users').doc(_uid).collection('bills').get()).docs.map((d) => d.id).toList();

  Future<void> open(WidgetTester tester, {double width = 390, double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 1800 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HistoricalBillListScreen(uid: _uid, firestoreService: service),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // แถวของเดือน [month] ในตาราง (ชื่อเดือนย่อในคอลัมน์แรก)
  Finder rowOf(DateTime month) => find.text(thaiMonthsShort[month.month - 1]).first;

  testWidgets('การ์ดสรุปบอกจำนวนบิลและเดือนที่ขาด', (tester) async {
    await addBill('b1', m1, 'imported');
    await addBill('b3', m3, 'imported');
    await open(tester);

    expect(find.text('มีบิลในระบบ 2 เดือน'), findsOneWidget);
    expect(find.textContaining('ขาดบิล 1 เดือน: ${short(m2)}'), findsOneWidget);
    expect(find.text('ยังไม่กรอก'), findsOneWidget);
  });

  testWidgets('บิลจากหน้าเลขมิเตอร์ -> ล็อก แก้/ลบที่นี่ไม่ได้', (tester) async {
    await addBill('b1', m1, 'startMeter');
    await open(tester);

    await tap(tester, rowOf(m1));
    expect(find.text('แก้ไขไม่ได้แล้ว'), findsOneWidget);
    expect(find.text('ไปหน้าเลขมิเตอร์จากใบแจ้งหนี้'), findsOneWidget);
  });

  testWidgets('บิลที่ระบบปิดให้ -> แก้ไขได้ แต่ไม่มีปุ่มลบ', (tester) async {
    await addBill('b1', m1, 'compiled');
    await open(tester);

    expect(find.text('ประมาณ'), findsOneWidget);
    await tap(tester, rowOf(m1));
    expect(find.text('แก้ไขรายการนี้'), findsOneWidget);
    expect(find.text('ลบรายการนี้'), findsNothing);
  });

  testWidgets('บิลที่กรอกเอง -> ลบได้ (ต้องยืนยันก่อน)', (tester) async {
    await addBill('b1', m1, 'imported');
    await open(tester);

    await tap(tester, rowOf(m1));
    await tap(tester, find.text('ลบรายการนี้'));
    expect(find.text('ลบบิลนี้?'), findsOneWidget);
    await tap(tester, find.text('ลบ'));

    expect(await billIds(), isEmpty);
  });

  testWidgets('ฟอร์ม: ไม่กรอกยอดเลย -> แจ้งในฟอร์มและไม่บันทึก', (tester) async {
    await open(tester);

    await tap(tester, find.text('เพิ่มบิลย้อนหลัง').last);
    await tap(tester, find.text('บันทึก'));

    expect(find.text('กรุณากรอกยอดค่าไฟหรือค่าน้ำอย่างน้อย 1 ฝั่งค่ะ'), findsOneWidget);
    expect(await billIds(), isEmpty);
  });

  testWidgets('ฟอร์ม: เดือนที่มีบิลแล้วกดเลือกไม่ได้ และบันทึกบิลเดือนว่างได้', (tester) async {
    await addBill('b1', m1, 'imported');
    await open(tester);

    await tap(tester, find.text('เพิ่มบิลย้อนหลัง').last);
    expect(find.text('มีบิลแล้ว'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), '850');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tap(tester, find.text('บันทึก'));

    final snapshot = await db.collection('users').doc(_uid).collection('bills').get();
    final saved = snapshot.docs.map((d) => d.data()).where((b) => b['id'] != 'b1').single;
    // เดือนแรกที่ยังว่าง (m1 มีบิลแล้ว จึงเลื่อนไป m2)
    expect(saved['month'], m2.month);
    expect(saved['electricityCost'], 850);
    expect(saved['source'], 'imported');
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> รายการและฟอร์มไม่ล้น', (tester) async {
    await addBill('b1', m1, 'compiled', cost: 98765.43);
    await addBill('b2', m2, 'startMeter', cost: 12345.67);
    await open(tester, width: 320, textScale: 1.3);
    expect(tester.takeException(), isNull);

    await tap(tester, find.text('เพิ่มบิลย้อนหลัง').last);
    expect(tester.takeException(), isNull);
  });
}
