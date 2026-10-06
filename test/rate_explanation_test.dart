// เทสหน้าอัตราค่าไฟฟ้า/น้ำ (lib/screens/settings/settings_rate_explanation.dart)
//
// ครอบ: ตารางที่แสดงตรงกับอัตราที่แอปใช้คิดจริงตามพื้นที่/มิเตอร์/ประเภทอัตรา
// (รหัสประเภทมาจาก tariffCode/touCode), ค่า Ft มาจากตัวโหลด และเตือนเมื่องวด Ft
// เก่าเกิน 4 เดือน, สลับไปแท็บน้ำได้ และเลย์เอาต์ไม่ล้นบนจอเล็ก
import 'package:energy_home/screens/settings/settings_screen.dart';
import 'package:energy_home/utils/calculator.dart';
import 'package:energy_home/utils/tariff_tables.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    String area = 'bangkok',
    String meterType = 'normal',
    String tariff = EnergyCalculator.tariffStandard,
    FtInfo ft = (rate: 0.1623, effectiveFrom: null),
    double width = 390,
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 2400 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RateExplanationScreen(area: area, meterType: meterType, tariff: tariff, ftLoader: () async => ft),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('MEA มิเตอร์ปกติ ประเภท 1.2 -> ตาราง 3 ขั้นและค่า Ft ที่โหลดมา', (tester) async {
    await open(tester);

    expect(find.text('การไฟฟ้านครหลวง (MEA)'), findsOneWidget);
    expect(find.textContaining('ประเภท 1.2 ใช้เกิน 150'), findsOneWidget);
    expect(find.text(TariffTables.electricityStandard.last.rate.toStringAsFixed(4)), findsOneWidget);
    expect(find.text('0.1623'), findsOneWidget);
    expect(find.textContaining('งวดใหม่อาจยังไม่ได้อัปเดต'), findsNothing);
  });

  testWidgets('PEA มิเตอร์ TOU -> อัตรา On/Off-Peak และรหัส 1.2.2', (tester) async {
    await open(tester, area: 'province', meterType: 'tou');

    expect(find.text('การไฟฟ้าส่วนภูมิภาค (PEA)'), findsOneWidget);
    expect(find.text('มิเตอร์ TOU · ประเภท 1.2.2'), findsOneWidget);
    expect(find.text(TariffTables.touPeakRate.toStringAsFixed(4)), findsOneWidget);
    expect(find.text(TariffTables.touOffPeakRate.toStringAsFixed(4)), findsOneWidget);
  });

  testWidgets('งวด Ft เก่าเกิน 4 เดือน -> ขึ้นคำเตือน', (tester) async {
    final old = DateTime.now().subtract(const Duration(days: 200));
    await open(tester, ft: (rate: 0.3972, effectiveFrom: old));

    expect(find.textContaining('งวดใหม่อาจยังไม่ได้อัปเดต'), findsOneWidget);
  });

  testWidgets('สลับไปน้ำ (PWA) -> ตารางแบ่ง 2 กลุ่มที่ 50 หน่วย', (tester) async {
    await open(tester, area: 'province');
    await tester.tap(find.text('น้ำ'));
    await tester.pumpAndSettle();

    expect(find.text('การประปาส่วนภูมิภาค (PWA)'), findsOneWidget);
    expect(find.text('ใช้ไม่เกิน 50 หน่วย'), findsOneWidget);
    expect(find.text('ใช้เกิน 50 หน่วย (หน่วยที่ 51 ขึ้นไป)'), findsOneWidget);
  });

  testWidgets('จอเล็ก (กว้าง 320) ตัวอักษรใหญ่สุดที่แอปอนุญาต -> ไม่ล้นทั้งสองแท็บ', (tester) async {
    await open(tester, meterType: 'tou', width: 320, textScale: 1.3);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('น้ำ'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
