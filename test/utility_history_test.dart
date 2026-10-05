// เทสหน้าประวัติการบันทึกมิเตอร์ (lib/screens/settings/settings_utility_log.dart)
// เปิดผ่าน openUtilityHistory() ตัวเดียวกับที่หน้าบันทึกมิเตอร์ใช้
//
// ครอบ: ยอดของรอบ = ค่าของรายการล่าสุด (usedFromStart/cost สะสมตั้งแต่ต้นรอบ
// ห้ามบวกกัน), ลบได้เฉพาะรายการในรอบปัจจุบัน (รอบที่ปิดแล้วขึ้นคำอธิบายแทน)
// และเลย์เอาต์ไม่ล้นบนจอเล็ก — รอบบิลคำนวณจากเวลาจริงด้วย EnergyForecaster
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/settings/settings_screen.dart' show openUtilityHistory;
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/utils/forecaster.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'u1';
const _billingDay = 1;

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreService service;
  final cycleStart = EnergyForecaster.getCycleStart(DateTime.now(), _billingDay);
  final prevCycleStart = EnergyForecaster.getPreviousCycleStart(cycleStart, _billingDay);

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = FirestoreService(firestore: db);
    await service.createUser(UserModel(uid: _uid, name: 'ทดสอบ', email: 'u1@example.com', billingDay: _billingDay));
  });

  Future<void> addLog(String id, DateTime date,
          {required double used, required double fromLast, required double cost}) =>
      service.saveElectricityLog(ElectricityLogModel(
        id: id,
        uid: _uid,
        date: date,
        meterValue: 10000 + used,
        usedFromStart: used,
        usedFromLast: fromLast,
        cost: cost,
      ));

  Future<void> open(WidgetTester tester, {double width = 390, double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => openUtilityHistory(context, _uid, service),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<int> logCount() async =>
      (await db.collection('users').doc(_uid).collection('electricity_logs').get()).docs.length;

  testWidgets('ยอดรอบปัจจุบัน = รายการล่าสุด ไม่ใช่ผลบวกของยอดสะสมทุกรายการ', (tester) async {
    // จด 2 ครั้งในรอบนี้: สะสม 70 หน่วย/294 บาท แล้ว 125 หน่วย/525 บาท
    await addLog('e1', cycleStart.add(const Duration(hours: 10)), used: 70, fromLast: 70, cost: 294);
    await addLog('e2', cycleStart.add(const Duration(hours: 30)), used: 125, fromLast: 55, cost: 525);
    await open(tester);

    expect(find.text('125 หน่วย'), findsWidgets);
    expect(find.text('525.00 บาท'), findsOneWidget);
    expect(find.text('2 ครั้ง'), findsOneWidget);
    // ผลบวกแบบผิดคือ 195 หน่วย / 819 บาท
    expect(find.textContaining('195'), findsNothing);
    expect(find.textContaining('819'), findsNothing);
  });

  testWidgets('ลบรายการในรอบปัจจุบันได้ (ต้องยืนยันก่อน)', (tester) async {
    await addLog('e1', cycleStart.add(const Duration(hours: 10)), used: 70, fromLast: 70, cost: 294);
    await open(tester);

    await tester.tap(find.text('+70 หน่วย'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบรายการนี้'));
    await tester.pumpAndSettle();
    expect(find.text('ต้องการลบข้อมูลนี้ใช่ไหมคะ?'), findsOneWidget);
    await tester.tap(find.text('ลบ'));
    await tester.pumpAndSettle();

    expect(await logCount(), 0);
  });

  testWidgets('รายการในรอบที่ปิดแล้ว -> ขึ้นคำอธิบายว่าแก้ไม่ได้ ไม่ลบ', (tester) async {
    await addLog('old', prevCycleStart.add(const Duration(days: 3)), used: 90, fromLast: 90, cost: 380);
    await open(tester);

    // รอบล่าสุดที่มีข้อมูลคือรอบก่อน จึงกางไว้ให้แล้ว
    await tester.tap(find.text('+90 หน่วย'));
    await tester.pumpAndSettle();
    expect(find.text('แก้ไขไม่ได้แล้ว'), findsOneWidget);
    expect(find.text('ลบรายการนี้'), findsNothing);
    await tester.tap(find.text('เข้าใจแล้ว'));
    await tester.pumpAndSettle();
    expect(await logCount(), 1);
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> ไม่ล้น', (tester) async {
    await addLog('e1', cycleStart.add(const Duration(hours: 10)), used: 12345, fromLast: 1234, cost: 98765.43);
    await addLog('old', prevCycleStart.add(const Duration(days: 3)), used: 23456, fromLast: 2345, cost: 87654.32);
    await open(tester, width: 320, textScale: 1.3);

    expect(tester.takeException(), isNull);
  });
}
