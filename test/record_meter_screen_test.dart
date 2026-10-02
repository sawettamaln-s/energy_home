// เทสหน้าบันทึกมิเตอร์ (lib/screens/dashboard/record_meter_screen.dart)
//
// กติกาที่ครอบ: เลขที่กรอกต้องไม่น้อยกว่าทั้งเลขต้นรอบและค่าที่บันทึกล่าสุด
// ของรอบนี้ (TOU เช็คทีละช่อง On-Peak/Off-Peak) ถ้าไม่ผ่านต้องบล็อกการบันทึก
// โชว์ข้อความใต้ช่องที่ผิด + คำแนะนำ/ปุ่มแก้ไขที่ตรงกับสาเหตุ ส่วนเลขที่ผ่าน
// ต้องบันทึก log ลง Firestore ด้วยค่า usedFromStart/usedFromLast ที่ถูกต้อง
//
// ใช้ FakeFirebaseFirestore แทนของจริง — EnergyCalculator.getFtRate() อ่าน
// FirebaseFirestore.instance ตรงๆ ซึ่งในเทสไม่มี Firebase จะ fallback เป็น
// ค่า Ft default เอง (เทสนี้จึงไม่ตรวจยอดเงิน ตรวจแค่หน่วย)
import 'package:energy_home/screens/dashboard/record_meter_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/utils/data_refresh_bus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'user-1';

void main() {
  late FakeFirebaseFirestore fakeDb;
  late FirestoreService service;

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    service = FirestoreService(firestore: fakeDb);
  });

  // เปิด RecordMeterScreen ผ่านการ push จริง (เหมือนที่แดชบอร์ดทำ) เพื่อให้
  // เทสผลลัพธ์ตอนหน้านี้ปิดตัวเองได้ — ผลลัพธ์ส่งกลับผ่าน onResult
  Future<void> openScreen(
    WidgetTester tester, {
    MeterKind kind = MeterKind.electricity,
    bool isTou = false,
    double startValue = 1000,
    double lastValue = 1100,
    double startPeak = 0,
    double lastPeak = 0,
    double startOffPeak = 0,
    double lastOffPeak = 0,
    ValueChanged<RecordMeterResult?>? onResult,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              final result = await Navigator.push<RecordMeterResult>(
                context,
                MaterialPageRoute(
                  builder: (_) => RecordMeterScreen(
                    kind: kind,
                    isTou: isTou,
                    uid: _uid,
                    firestoreService: service,
                    area: 'bangkok',
                    startValue: startValue,
                    lastValue: lastValue,
                    startPeak: startPeak,
                    lastPeak: lastPeak,
                    startOffPeak: startOffPeak,
                    lastOffPeak: lastOffPeak,
                  ),
                ),
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // พิมพ์ลงช่องที่ index แล้วรอให้ debounce (500ms) + การคำนวณเสร็จ
  Future<void> enterAndCalc(WidgetTester tester, int fieldIndex, String text) async {
    await tester.enterText(find.byType(TextField).at(fieldIndex), text);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // ปุ่ม "ยืนยันบันทึก" กดได้ไหม (ปิดไว้เมื่อมีช่องที่เลขไม่ผ่านการเช็ค)
  bool saveEnabled(WidgetTester tester) => tester
      .widget<ElevatedButton>(find.ancestor(
          of: find.text('ยืนยันบันทึก'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)))
      .enabled;

  Future<List<Map<String, dynamic>>> savedLogs(String collection) async {
    final snapshot = await fakeDb
        .collection('users')
        .doc(_uid)
        .collection(collection)
        .get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  const belowStartHelp = 'หากเพิ่งเปลี่ยนมิเตอร์ใหม่ กรุณาตั้งเลขมิเตอร์ต้นรอบใหม่ก่อนบันทึกค่ะ';
  const startSetupButton = 'ตั้งเลขมิเตอร์ต้นรอบใหม่';
  const historyButton = 'ไปที่ประวัติการบันทึกมิเตอร์';

  group('มิเตอร์ปกติ', () {
    testWidgets('เลขมากกว่าค่าล่าสุด -> บันทึกได้ พร้อมหน่วยจากต้นรอบ/ครั้งล่าสุดถูกต้อง',
        (tester) async {
      await openScreen(tester);
      await enterAndCalc(tester, 0, '1150');
      await tapButton(tester, 'ยืนยันบันทึก');

      expect(find.text('บันทึกสำเร็จ'), findsWidgets);
      final logs = await savedLogs('electricity_logs');
      expect(logs, hasLength(1));
      expect(logs.single['meterValue'], 1150);
      expect(logs.single['usedFromStart'], 150);
      expect(logs.single['usedFromLast'], 50);
    });

    testWidgets('เลขเท่ากับค่าล่าสุดพอดี -> บันทึกได้ (ยังไม่ได้ใช้เพิ่ม)',
        (tester) async {
      await openScreen(tester);
      await enterAndCalc(tester, 0, '1100');
      await tapButton(tester, 'ยืนยันบันทึก');

      final logs = await savedLogs('electricity_logs');
      expect(logs, hasLength(1));
      expect(logs.single['usedFromLast'], 0);
    });

    testWidgets('รองรับตัวเลขที่มี comma คั่นหลักพัน', (tester) async {
      await openScreen(tester);
      await enterAndCalc(tester, 0, '1,150');
      await tapButton(tester, 'ยืนยันบันทึก');

      final logs = await savedLogs('electricity_logs');
      expect(logs.single['meterValue'], 1150);
    });

    testWidgets('ต่ำกว่าเลขต้นรอบ -> บล็อก + แนะนำตั้งต้นรอบใหม่ ไม่บันทึก',
        (tester) async {
      await openScreen(tester);
      await enterAndCalc(tester, 0, '900');

      expect(find.text('เลขมิเตอร์ต้องไม่น้อยกว่าเลขต้นรอบบิล (1,000 หน่วย) ค่ะ'),
          findsOneWidget);
      expect(find.text(belowStartHelp), findsOneWidget);
      expect(find.text(startSetupButton), findsOneWidget);
      expect(find.text(historyButton), findsNothing);
      expect(saveEnabled(tester), isFalse);
      expect(await savedLogs('electricity_logs'), isEmpty);
    });

    testWidgets('ไม่ต่ำกว่าต้นรอบแต่ต่ำกว่าค่าล่าสุด -> บล็อก + แนะนำลบรายการล่าสุด',
        (tester) async {
      await openScreen(tester);
      await enterAndCalc(tester, 0, '1050');

      expect(
          find.text('เลขมิเตอร์ต้องไม่น้อยกว่าค่าที่บันทึกล่าสุด (1,100 หน่วย) ค่ะ'),
          findsOneWidget);
      expect(find.textContaining('ตั้งค่า › ประวัติการบันทึกมิเตอร์'), findsOneWidget);
      expect(find.text(historyButton), findsOneWidget);
      expect(find.text(startSetupButton), findsNothing);
      expect(saveEnabled(tester), isFalse);
      expect(await savedLogs('electricity_logs'), isEmpty);
    });

    testWidgets('ปุ่มบันทึกปิดอยู่ -> พิมพ์แก้ให้ถูกแล้วปุ่มกลับมากดได้ และบันทึกได้',
        (tester) async {
      await openScreen(tester);
      await enterAndCalc(tester, 0, '1050');
      expect(saveEnabled(tester), isFalse);

      // เริ่มพิมพ์แก้ปุ๊บ ปุ่มต้องกดได้ทันที ไม่ต้องรอคำนวณเสร็จ
      await tester.enterText(find.byType(TextField).first, '1150');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.textContaining('ต้องไม่น้อยกว่า'), findsNothing);
      await tapButton(tester, 'ยืนยันบันทึก');
      expect((await savedLogs('electricity_logs')).single['meterValue'], 1150);
    });

    testWidgets('กรอกไม่ใช่ตัวเลข -> แจ้งรูปแบบไม่ถูกต้อง ไม่มีปุ่มแนะนำ',
        (tester) async {
      await openScreen(tester);
      await enterAndCalc(tester, 0, 'abc');

      expect(find.text('รูปแบบตัวเลขไม่ถูกต้อง กรุณากรอกเฉพาะตัวเลขค่ะ'),
          findsOneWidget);
      expect(find.text(startSetupButton), findsNothing);
      expect(find.text(historyButton), findsNothing);
      expect(saveEnabled(tester), isFalse);
      expect(await savedLogs('electricity_logs'), isEmpty);
    });

    testWidgets('ไม่กรอกอะไรเลยแล้วกดบันทึก -> ปุ่มยังกดได้ และแจ้งให้กรอกก่อน',
        (tester) async {
      await openScreen(tester);
      expect(saveEnabled(tester), isTrue);
      await tapButton(tester, 'ยืนยันบันทึก');

      expect(find.text('กรุณากรอกเลขมิเตอร์ไฟฟ้าก่อนบันทึกค่ะ'), findsOneWidget);
      expect(await savedLogs('electricity_logs'), isEmpty);
    });

    testWidgets('น้ำ: ต้นรอบเป็น 0 กรอก 0 -> บันทึกได้ (มิเตอร์ใหม่ยังไม่ได้ใช้)',
        (tester) async {
      await openScreen(tester,
          kind: MeterKind.water, startValue: 0, lastValue: 0);
      await enterAndCalc(tester, 0, '0');
      await tapButton(tester, 'ยืนยันบันทึก');

      final logs = await savedLogs('water_logs');
      expect(logs, hasLength(1));
      expect(logs.single['meterValue'], 0);
      expect(logs.single['usedFromStart'], 0);
    });
  });

  group('มิเตอร์ TOU (เช็คทีละช่อง)', () {
    Future<void> openTou(WidgetTester tester) => openScreen(
          tester,
          isTou: true,
          startPeak: 100,
          lastPeak: 150,
          startOffPeak: 200,
          lastOffPeak: 260,
        );

    testWidgets('เว้นช่อง Off-Peak -> ใช้ค่าล่าสุดแทน และบันทึกได้',
        (tester) async {
      await openTou(tester);
      await enterAndCalc(tester, 0, '170');
      await tapButton(tester, 'ยืนยันบันทึก');

      final logs = await savedLogs('electricity_logs');
      expect(logs, hasLength(1));
      expect(logs.single['peakMeterValue'], 170);
      expect(logs.single['offPeakMeterValue'], 260);
      expect(logs.single['usedFromStart'], 130); // (170-100) + (260-200)
      expect(logs.single['usedFromLast'], 20); // (170-150) + 0
    });

    testWidgets('On-Peak ต่ำกว่าค่าล่าสุด -> ข้อความเฉพาะช่อง On-Peak และบล็อก',
        (tester) async {
      await openTou(tester);
      await enterAndCalc(tester, 0, '140');

      expect(
          find.text('เลข On-Peak (T1) ต้องไม่น้อยกว่าค่าที่บันทึกล่าสุด (150 หน่วย) ค่ะ'),
          findsOneWidget);
      expect(find.textContaining('เลข Off-Peak (T2)'), findsNothing);
      expect(find.text(historyButton), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      expect(await savedLogs('electricity_logs'), isEmpty);
    });

    testWidgets('ช่องหนึ่งต่ำกว่าต้นรอบ อีกช่องต่ำกว่าล่าสุด -> โชว์ทั้งสองข้อความ แนะนำเรื่องต้นรอบก่อน',
        (tester) async {
      await openTou(tester);
      await tester.enterText(find.byType(TextField).at(0), '90');
      await enterAndCalc(tester, 1, '250');

      expect(
          find.text('เลข On-Peak (T1) ต้องไม่น้อยกว่าเลขต้นรอบบิล (100 หน่วย) ค่ะ'),
          findsOneWidget);
      expect(
          find.text('เลข Off-Peak (T2) ต้องไม่น้อยกว่าค่าที่บันทึกล่าสุด (260 หน่วย) ค่ะ'),
          findsOneWidget);
      expect(find.text(startSetupButton), findsOneWidget);
      expect(find.text(historyButton), findsNothing);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('ไม่กรอกทั้งสองช่องแล้วกดบันทึก -> แจ้งให้กรอกอย่างน้อย 1 ช่อง',
        (tester) async {
      await openTou(tester);
      await tapButton(tester, 'ยืนยันบันทึก');

      expect(
          find.text(
              'กรุณากรอกเลขมิเตอร์ On-Peak (T1) หรือ Off-Peak (T2) อย่างน้อย 1 ช่องค่ะ'),
          findsOneWidget);
      expect(await savedLogs('electricity_logs'), isEmpty);
    });
  });

  group('ปุ่มไปหน้าประวัติการบันทึกมิเตอร์', () {
    Future<void> openHistoryFromBelowLast(
      WidgetTester tester, {
      MeterKind kind = MeterKind.electricity,
      ValueChanged<RecordMeterResult?>? onResult,
    }) async {
      await openScreen(tester, kind: kind, onResult: onResult);
      await enterAndCalc(tester, 0, '1050');
      await tapButton(tester, historyButton);
    }

    void popHistory(WidgetTester tester) {
      Navigator.of(tester.element(find.byType(TabBar))).pop();
    }

    testWidgets('เปิดจากหน้าน้ำ -> เปิดที่แท็บประปา', (tester) async {
      await openHistoryFromBelowLast(tester, kind: MeterKind.water);

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.controller!.index, 1);
    });

    testWidgets('กลับมาโดยไม่ได้แก้ข้อมูล -> อยู่หน้าบันทึกต่อ', (tester) async {
      RecordMeterResult? result;
      var closed = false;
      await openHistoryFromBelowLast(tester, onResult: (r) {
        closed = true;
        result = r;
      });

      popHistory(tester);
      await tester.pumpAndSettle();

      expect(closed, isFalse);
      expect(result, isNull);
      expect(find.text('ยืนยันบันทึก'), findsOneWidget);
    });

    testWidgets('กลับมาหลังมีการแก้ข้อมูล -> ปิดหน้าบันทึกกลับไปให้โหลดใหม่',
        (tester) async {
      RecordMeterResult? result;
      await openHistoryFromBelowLast(tester, onResult: (r) => result = r);

      // จำลองการลบ log ในหน้าประวัติ (FirestoreService แจ้ง bus ทุกครั้งที่ลบ)
      DataRefreshBus.instance.notifyChanged();
      popHistory(tester);
      await tester.pumpAndSettle();

      expect(result?.saved, isTrue);
      expect(find.text('ยืนยันบันทึก'), findsNothing);
    });
  });
}
