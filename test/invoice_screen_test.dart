// เทสหน้าใบแจ้งหนี้ (lib/screens/settings/settings_invoices.dart + ฟอร์มใบเดือนก่อนๆ
// settings_bill_form.dart) ด้วย FakeFirebaseFirestore
//
// ครอบ: การ์ดใบเดือนก่อนๆ บอกเดือนที่ขาด, กติกาตามที่มาของบิล (ใบเก่าจากเลขมิเตอร์
// แก้ไม่ได้, ระบบประมาณแก้ได้แต่ลบไม่ได้, กรอกเองลบได้), เลขมิเตอร์กับบิลของใบเดียวกัน
// อยู่แถวเดียวกัน, ฟอร์มกรอกไม่ครบแจ้งในฟอร์มและไม่บันทึก, บันทึกใบใหม่ได้ และ
// เลย์เอาต์ไม่ล้นบนจอเล็ก — รอบบิลคำนวณจากเวลาจริง
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/models/start_meter_record_model.dart';
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
      home: InvoiceScreen(uid: _uid, firestoreService: service),
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

  Future<void> addRecord(String id, DateTime month, double electricity) => service.saveStartMeterRecord(
        StartMeterRecordModel(
          id: id,
          uid: _uid,
          electricityValue: electricity,
          waterValue: 0,
          billingMonth: month.month,
          billingYear: month.year,
          recordedAt: month,
        ),
      );

  testWidgets('การ์ดใบเดือนก่อนๆ บอกจำนวนใบและเดือนที่ขาด', (tester) async {
    await addBill('b1', m1, 'imported');
    await addBill('b3', m3, 'imported');
    await open(tester);

    expect(find.text('มี 2 เดือน ย้อนหลังถึง ${thaiMonths[m3.month - 1]} ${m3.year + 543}'), findsOneWidget);
    expect(find.textContaining('ขาดบิล 1 เดือน: ${short(m2)}'), findsOneWidget);
    expect(find.text('ยังไม่กรอก'), findsOneWidget);
    expect(find.text('กรอกเอง'), findsNWidgets(2));
  });

  testWidgets('เลขมิเตอร์กับบิลของใบเดียวกัน (เดือนเดียวกัน) อยู่แถวเดียว สลับดูเลขมิเตอร์ได้', (tester) async {
    // ใบ m2 และ m1 กรอกจากเลขมิเตอร์: record กับบิล startMeter ใช้ปี/เดือนเดียวกัน
    await addRecord('r2', m2, 5000);
    await addRecord('r1', m1, 5300);
    await addBill('b2', m2, 'startMeter');
    await addBill('b1', m1, 'startMeter', cost: 1200);
    await open(tester);

    // หนึ่งเดือนต่อหนึ่งแถว ไม่ใช่ record แถวหนึ่ง บิลอีกแถว
    expect(rowOf(m1), findsOneWidget);
    expect(find.text('1,200.00'), findsOneWidget);

    await tap(tester, find.text('เลขมิเตอร์'));
    expect(find.text('5,300'), findsOneWidget);
    expect(find.text('5,000'), findsOneWidget);
    // หน่วยของใบ m1 มาจากบิล (250) — ตรงแถวเดียวกับเลข 5,300
    final m1Row = find.ancestor(of: find.text('5,300'), matching: find.byType(InkWell)).first;
    expect(find.descendant(of: m1Row, matching: find.text('250')), findsOneWidget);
    expect(find.descendant(of: m1Row, matching: rowOf(m1)), findsOneWidget);
  });

  testWidgets('เดือนที่ขาดนับย้อนถึงใบแรกสุดที่กรอกเลขต้นรอบ แม้เดือนตั้งต้นของ user เป็นเดือนล่าสุดแล้ว',
      (tester) async {
    // user ตั้งต้นรอบปัจจุบันไปแล้ว (startBillingMonth ถูกเขียนทับเป็นเดือนล่าสุด) แต่เริ่ม
    // ติดตามตั้งแต่ m3 — m2 ที่ไม่มีบิลต้องยังขึ้นว่าขาด
    await service.updateUser(_uid, {'startBillingMonth': current.month, 'startBillingYear': current.year});
    await addRecord('r3', m3, 5000);
    await addBill('b3', m3, 'startMeter');
    await addBill('b1', m1, 'compiled');
    await open(tester);

    expect(find.textContaining('ขาดบิล 1 เดือน: ${short(m2)}'), findsOneWidget);
  });

  testWidgets('บิลย้อนหลังครบ 5 เดือนและไม่มีเดือนที่ขาด -> เหลือบรรทัดบางๆ ไม่มีการ์ดและปุ่มเพิ่ม', (tester) async {
    var m = m1;
    for (var i = 0; i < 5; i++) {
      if (i > 0) m = EnergyForecaster.getPreviousCycleStart(m, _billingDay);
      await addBill('p$i', m, 'imported');
    }
    // เริ่มใช้แอปตั้งแต่เดือนของบิลเก่าสุด — ไม่มีเดือนที่ขาด
    await service.updateUser(_uid, {'startBillingMonth': m.month, 'startBillingYear': m.year});
    await open(tester);

    expect(find.text('บันทึกบิลย้อนหลังครบแล้ว แก้ไขได้ในตารางด้านล่างค่ะ'), findsOneWidget);
    expect(find.text('เพิ่มบิลย้อนหลัง'), findsNothing);
    expect(find.text('ไม่บังคับ'), findsNothing);
  });

  testWidgets('ใบเก่าจากเลขมิเตอร์ -> แก้เลขไม่ได้ (บอกเหตุผล) แต่ลบข้อมูลรายฝั่งได้', (tester) async {
    await addRecord('r1', m1, 5300);
    await addBill('b1', m1, 'startMeter');
    await open(tester);

    await tap(tester, rowOf(m1));
    expect(find.textContaining('บิลของรอบที่ผ่านมาแล้วแก้เลขมิเตอร์ไม่ได้'), findsOneWidget);
    expect(find.text('แก้ไข'), findsNothing);
    expect(find.text('ลบข้อมูลไฟฟ้าของบิลนี้'), findsOneWidget);
  });

  testWidgets('บิลที่ระบบประมาณ -> ใส่ยอดจริงได้ แต่ไม่มีปุ่มลบ', (tester) async {
    await addBill('b1', m1, 'compiled');
    await open(tester);

    expect(find.text('ระบบประมาณ'), findsOneWidget);
    await tap(tester, rowOf(m1));
    expect(find.text('ใส่ยอดจากใบแจ้งหนี้จริง'), findsOneWidget);
    expect(find.text('ลบบิลนี้'), findsNothing);

    await tap(tester, find.text('ใส่ยอดจากใบแจ้งหนี้จริง'));
    expect(find.text('แก้ไขบิลย้อนหลัง'), findsOneWidget);
  });

  testWidgets('ใบที่กรอกเอง -> ลบได้ (ต้องยืนยันก่อน)', (tester) async {
    await addBill('b1', m1, 'imported');
    await open(tester);

    await tap(tester, rowOf(m1));
    await tap(tester, find.text('ลบบิลนี้'));
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
