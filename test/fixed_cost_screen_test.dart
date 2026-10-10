// เทสหน้ารายจ่ายประจำ (lib/screens/settings/settings_fixed_cost.dart) ด้วย
// FakeFirebaseFirestore
//
// ครอบ: ยอด/จำนวนบนการ์ดนับเฉพาะรายการที่ใช้อยู่เดือนนี้ (สิ้นสุดแล้ว/ยังไม่เริ่ม
// แยกกลุ่ม ไม่นับ), ฟอร์มกรอกไม่ครบแจ้งในฟอร์มและไม่บันทึก, เพิ่มรายการหมวด
// สำเร็จรูปได้ชื่อตามหมวด, ลบต้องยืนยัน และเลย์เอาต์ไม่ล้นบนจอเล็ก
import 'package:energy_home/models/fixed_cost_item_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/settings/settings_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'u1';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreService service;
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month);

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = FirestoreService(firestore: db);
    await service.createUser(UserModel(uid: _uid, name: 'ทดสอบ', email: 'u1@example.com'));
  });

  Future<void> addItem(String id, String name, double amount, {required DateTime start, DateTime? end}) =>
      service.saveFixedCostItem(FixedCostItemModel(
        id: id,
        uid: _uid,
        name: name,
        category: 'other',
        amount: amount,
        createdAt: start,
        startDate: start,
        endDate: end,
      ));

  Future<List<Map<String, dynamic>>> items() async =>
      (await db.collection('users').doc(_uid).collection('fixed_costs').get()).docs.map((d) => d.data()).toList();

  Future<void> open(WidgetTester tester, {double width = 390, double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 1800 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FixedCostScreen(uid: _uid, firestoreService: service),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('การ์ดนับเฉพาะรายการที่ใช้อยู่ ส่วนที่สิ้นสุด/ยังไม่เริ่มแยกกลุ่ม', (tester) async {
    await addItem('a', 'อินเทอร์เน็ต', 599, start: DateTime(thisMonth.year, thisMonth.month - 3));
    await addItem('b', 'ประกันเก่า', 1000,
        start: DateTime(thisMonth.year - 1, thisMonth.month), end: DateTime(thisMonth.year, thisMonth.month - 2));
    await addItem('c', 'ค่าเรียน', 2000, start: DateTime(thisMonth.year, thisMonth.month + 2));
    await open(tester);

    expect(find.text('599 บาท'), findsWidgets);
    expect(find.textContaining('1 รายการที่ใช้อยู่'), findsOneWidget);
    expect(find.text('ใช้อยู่ (1)'), findsOneWidget);
    expect(find.text('ยังไม่เริ่ม (1)'), findsOneWidget);
    expect(find.text('สิ้นสุดแล้ว (1)'), findsOneWidget);
    // กลุ่มสิ้นสุดแล้วพับไว้ กดแล้วจึงเห็นรายการ
    expect(find.text('ประกันเก่า'), findsNothing);
    await tap(tester, find.text('สิ้นสุดแล้ว (1)'));
    expect(find.text('ประกันเก่า'), findsOneWidget);
  });

  testWidgets('ฟอร์ม: ไม่กรอกยอด -> แจ้งในฟอร์มและไม่บันทึก', (tester) async {
    await open(tester);

    await tap(tester, find.text('เพิ่มรายจ่ายประจำ'));
    await tap(tester, find.text('บันทึก'));

    expect(find.text('กรอกยอดเงินต่อเดือนให้ถูกต้องด้วยค่ะ'), findsOneWidget);
    expect(await items(), isEmpty);
  });

  testWidgets('ฟอร์ม: หมวด "อื่นๆ" ไม่กรอกชื่อ -> แจ้งให้กรอกชื่อ', (tester) async {
    await open(tester);

    await tap(tester, find.text('เพิ่มรายจ่ายประจำ'));
    await tap(tester, find.text('อื่นๆ'));
    await tester.enterText(find.byType(TextField).last, '300');
    await tap(tester, find.text('บันทึก'));

    expect(find.text('กรอกชื่อรายการด้วยค่ะ'), findsOneWidget);
    expect(await items(), isEmpty);
  });

  testWidgets('ฟอร์ม: กรอกยอดก่อนแล้วค่อยเลือก "อื่นๆ" -> ช่องยอดเงินยังเป็นช่องเดิม ช่องชื่อเป็นช่องใหม่ที่พิมพ์ตัวอักษรได้',
      (tester) async {
    await open(tester);
    await tap(tester, find.text('เพิ่มรายจ่ายประจำ'));
    // พิมพ์ยอดก่อน (คีย์บอร์ดตัวเลขเปิดค้างอยู่ที่ช่องนี้)
    await tester.enterText(find.byType(TextField).last, '599');
    await tester.pump();
    await tap(tester, find.text('อื่นๆ'));

    EditableText editable(Finder field) =>
        tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)));
    final nameField = find.widgetWithText(TextField, 'เช่น ค่าที่จอดรถรายเดือน');
    final amountField = find.widgetWithText(TextField, 'เช่น 599');
    // ช่องที่ยังโฟกัสอยู่ต้องเป็นช่องยอดเงินตัวเดิม ไม่ใช่ช่องชื่อที่เพิ่งโผล่มาแทนที่ตำแหน่งเดิม
    expect(editable(amountField).controller.text, '599');
    expect(editable(amountField).focusNode.hasFocus, isTrue);
    expect(editable(nameField).focusNode.hasFocus, isFalse);
    expect(editable(nameField).keyboardType, TextInputType.text);
  });

  testWidgets('ฟอร์ม: เพิ่มหมวดสำเร็จรูป -> ชื่อตามหมวด เริ่มเดือนนี้ ไม่มีวันสิ้นสุด', (tester) async {
    await open(tester);

    await tap(tester, find.text('เพิ่มรายจ่ายประจำ'));
    await tap(tester, find.text('ค่าอินเทอร์เน็ตบ้าน'));
    await tester.enterText(find.byType(TextField).last, '599');
    await tap(tester, find.text('บันทึก'));

    final saved = (await items()).single;
    expect(saved['name'], 'ค่าอินเทอร์เน็ตบ้าน');
    expect(saved['category'], 'internet');
    expect(saved['amount'], 599);
    expect(saved['endDate'], isNull);
    expect(find.text('ใช้อยู่ (1)'), findsOneWidget);
  });

  testWidgets('แตะแถว -> ลบได้ (ต้องยืนยันก่อน)', (tester) async {
    await addItem('a', 'อินเทอร์เน็ต', 599, start: thisMonth);
    await open(tester);

    await tap(tester, find.text('อินเทอร์เน็ต'));
    await tap(tester, find.text('ลบรายการนี้'));
    expect(find.text('ลบรายการนี้?'), findsOneWidget);
    await tap(tester, find.text('ลบ'));

    expect(await items(), isEmpty);
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> รายการและฟอร์มไม่ล้น', (tester) async {
    await addItem('a', 'ค่าสมาชิกบริการสตรีมมิ่งรายเดือนแบบครอบครัว', 98765, start: thisMonth);
    await addItem('b', 'ประกันเก่า', 1000,
        start: DateTime(thisMonth.year - 1, thisMonth.month), end: DateTime(thisMonth.year, thisMonth.month - 2));
    await open(tester, width: 320, textScale: 1.3);
    await tap(tester, find.text('สิ้นสุดแล้ว (1)'));
    expect(tester.takeException(), isNull);

    await tap(tester, find.text('เพิ่มรายจ่ายประจำ'));
    await tap(tester, find.text('อื่นๆ'));
    expect(tester.takeException(), isNull);
  });
}
