// เทสหน้าอุปกรณ์ (lib/screens/appliance/) ด้วย FakeFirebaseFirestore และ
// MockFirebaseAuth — ครอบ: การ์ดสรุป/รายการ, กดการ์ดเปิดรายละเอียด, ลบจาก
// หน้ารายละเอียด (มีกล่องยืนยัน), เพิ่มอุปกรณ์จากรายการสามัญ และการตรวจค่าใน
// ฟอร์ม (เวลาเกิน 24 ชม. / กำลังไฟไม่ใช่ตัวเลข ต้องบันทึกไม่ได้)
import 'package:energy_home/models/appliance_model.dart';
import 'package:energy_home/screens/appliance/appliance_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'u1';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = FirestoreService(firestore: db);
  });

  Future<void> addAircon() => service.saveAppliance(ApplianceModel(
        id: 'a1',
        uid: _uid,
        name: 'แอร์ห้องนอน',
        watt: 900,
        iconKey: 'ac_unit',
        schedules: [ScheduleModel(days: const [0, 1, 2, 3, 4, 5, 6], startTime: '00:00', endTime: '08:00')],
      ));

  Future<List<Map<String, dynamic>>> savedAppliances() async {
    final snapshot = await db.collection('users').doc(_uid).collection('appliances').get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  Future<void> pumpScreen(WidgetTester tester, {double width = 390, double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 844 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ApplianceScreen(
        firestoreService: service,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // เปิดฟอร์มเพิ่มอุปกรณ์ แล้วเลือก "เครื่องปรับอากาศ (Inverter)" จากรายการสามัญ
  Future<void> openFormWithInverterAircon(WidgetTester tester) async {
    await tap(tester, find.text('เพิ่มอุปกรณ์'));
    await tap(tester, find.text('เครื่องปรับอากาศ (Inverter)'));
  }

  // ช่องในฟอร์ม: 0 ชื่อ, 1 กำลังไฟ, 2 ชั่วโมง, 3 นาที
  Finder field(int i) => find.byType(TextField).at(i);

  testWidgets('ยังไม่มีอุปกรณ์ -> หน้าว่างพร้อมปุ่มเพิ่มชิ้นแรก', (tester) async {
    await pumpScreen(tester);

    expect(find.text('ยังไม่มีเครื่องใช้ไฟฟ้า'), findsOneWidget);
    expect(find.text('เพิ่มอุปกรณ์ชิ้นแรก'), findsOneWidget);
  });

  testWidgets('มีอุปกรณ์ -> การ์ดสรุปและการ์ดอุปกรณ์ กดการ์ดเปิดรายละเอียดที่มีปุ่มแก้ไข/ลบ',
      (tester) async {
    await addAircon();
    await pumpScreen(tester);

    // การ์ดบนสุดบอกเครื่องที่กินไฟมากที่สุด ชื่อจึงขึ้นทั้งในการ์ดและในรายการ
    expect(find.text('กินไฟมากที่สุด'), findsOneWidget);
    expect(find.text('แอร์ห้องนอน'), findsNWidgets(2));
    expect(find.text('ทุกวัน · วันละ 8 ชม.'), findsOneWidget);

    await tap(tester, find.text('แอร์ห้องนอน').last);
    expect(find.text('แก้ไข'), findsOneWidget);
    expect(find.text('ลบ'), findsOneWidget);
  });

  testWidgets('ลบจากหน้ารายละเอียด -> ถามยืนยันก่อน แล้วลบออกจาก Firestore', (tester) async {
    await addAircon();
    await pumpScreen(tester);

    await tap(tester, find.text('แอร์ห้องนอน').last);
    await tap(tester, find.text('ลบ'));
    expect(find.text('ต้องการลบ "แอร์ห้องนอน" ใช่ไหมคะ'), findsOneWidget);

    await tap(tester, find.widgetWithText(TextButton, 'ลบ'));
    expect(await savedAppliances(), isEmpty);
  });

  testWidgets('เพิ่มจากรายการสามัญ + ปุ่มลัด 8 ชม. -> บันทึกชื่อ/วัตต์/เวลา/วันถูกต้อง', (tester) async {
    await addAircon();
    await pumpScreen(tester);
    await openFormWithInverterAircon(tester);

    expect(tester.widget<TextField>(field(1)).controller!.text, '900');
    await tap(tester, find.text('8 ชม.'));
    await tap(tester, find.text('จ–ศ'));
    await tap(tester, find.text('บันทึก'));

    final saved = (await savedAppliances()).where((a) => a['id'] != 'a1').single;
    expect(saved['name'], 'เครื่องปรับอากาศ (Inverter)');
    expect(saved['watt'], 900);
    expect(saved['iconKey'], 'ac_unit');
    final schedule = (saved['schedules'] as List).single as Map;
    expect(schedule['endTime'], '08:00');
    expect(schedule['days'], [0, 1, 2, 3, 4]);
  });

  testWidgets('เวลาเกิน 24 ชม. -> แจ้งใต้ช่องและไม่บันทึก พิมพ์แก้แล้วข้อความหาย', (tester) async {
    await addAircon();
    await pumpScreen(tester);
    await openFormWithInverterAircon(tester);

    await tester.enterText(field(2), '30');
    await tap(tester, find.text('บันทึก'));
    expect(find.text('ใช้งานได้ไม่เกิน 24 ชั่วโมงต่อวันค่ะ'), findsOneWidget);
    expect(await savedAppliances(), hasLength(1));

    await tester.enterText(field(2), '10');
    await tester.pumpAndSettle();
    expect(find.text('ใช้งานได้ไม่เกิน 24 ชั่วโมงต่อวันค่ะ'), findsNothing);
  });

  testWidgets('กำลังไฟไม่ใช่ตัวเลข / เวลาเป็น 0 -> แจ้งทั้งสองช่องและไม่บันทึก', (tester) async {
    await addAircon();
    await pumpScreen(tester);
    await openFormWithInverterAircon(tester);

    await tester.enterText(field(1), 'abc');
    await tester.enterText(field(2), '0');
    await tap(tester, find.text('บันทึก'));

    expect(find.text('กรุณากรอกกำลังไฟเป็นตัวเลขที่มากกว่า 0 ค่ะ'), findsOneWidget);
    expect(find.text('กรุณาระบุเวลาที่ใช้ต่อวันค่ะ'), findsOneWidget);
    expect(await savedAppliances(), hasLength(1));
  });

  testWidgets('กำลังไฟนอกช่วงทั่วไป -> เตือนแต่ยังบันทึกได้', (tester) async {
    await addAircon();
    await pumpScreen(tester);
    await openFormWithInverterAircon(tester);

    await tester.enterText(field(1), '5000');
    await tester.pumpAndSettle();
    expect(find.textContaining('สูงกว่าช่วงทั่วไป'), findsOneWidget);

    await tap(tester, find.text('บันทึก'));
    expect(await savedAppliances(), hasLength(2));
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> รายการ/ตารางเลือก/ฟอร์มไม่ล้น',
      (tester) async {
    await service.saveAppliance(ApplianceModel(
      id: 'a2',
      uid: _uid,
      name: 'เครื่องปรับอากาศห้องนอนใหญ่ชั้นสองฝั่งทิศตะวันตก',
      watt: 12000,
      schedules: [ScheduleModel(days: const [0, 2, 4], startTime: '00:00', endTime: '23:30')],
    ));
    await pumpScreen(tester, width: 320, textScale: 1.3);
    expect(tester.takeException(), isNull);

    await tap(tester, find.text('เพิ่มอุปกรณ์'));
    expect(tester.takeException(), isNull);

    await tap(tester, find.text('เครื่องปรับอากาศ (Fixed Speed)'));
    expect(tester.takeException(), isNull);
  });
}
