// เทสเครื่องคิดค่าไฟ/ค่าน้ำจากหน่วย (lib/widgets/quick_cost_sheet.dart): ยอดรวมต้องเท่ากับ
// สูตรที่แอปใช้คิดบิลจริง (TariffTables) ตามพื้นที่/ประเภทมิเตอร์/ประเภทอัตรา และยอดแยกส่วน
// รวมกันได้เท่ายอดรวม
import 'package:energy_home/utils/calculator.dart';
import 'package:energy_home/utils/tariff_tables.dart';
import 'package:energy_home/widgets/quick_cost_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  const ft = 0.1623;
  final money = NumberFormat('#,##0.00');

  Future<void> open(WidgetTester tester, {String area = 'bangkok', String meterType = 'normal', String tariff = 'standard'}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuickCostSheet(
          area: area,
          meterType: meterType,
          tariff: tariff,
          ftLoader: () async => (rate: ft, effectiveFrom: null),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('ไฟฟ้ามิเตอร์ปกติ -> ยอดเท่าสูตรคิดบิลจริงของประเภทอัตราที่เลือก', (tester) async {
    await open(tester, tariff: EnergyCalculator.tariffSmall);
    await tester.enterText(find.byType(TextField), '120');
    await tester.pump();

    final total = EnergyCalculator.electricityCost(120, ftRate: ft, tariff: EnergyCalculator.tariffSmall);
    expect(find.text('${money.format(total)} บาท'), findsOneWidget);
    expect(find.textContaining('อัตราประเภท 1.1 '), findsOneWidget);
  });

  testWidgets('TOU -> กรอก On/Off-Peak แยกกัน ยอดเท่าสูตร TOU', (tester) async {
    await open(tester, area: 'province', meterType: 'tou');
    await tester.enterText(find.byType(TextField).at(0), '100');
    await tester.enterText(find.byType(TextField).at(1), '200');
    await tester.pump();

    final total = EnergyCalculator.electricityTouCost(peakUnits: 100, offPeakUnits: 200, ftRate: ft);
    expect(find.text('${money.format(total)} บาท'), findsOneWidget);
    expect(find.textContaining('อัตราประเภท 1.2.2 '), findsOneWidget);
  });

  testWidgets('น้ำ กปภ. -> ยอดเท่าสูตรค่าน้ำ ไม่มีบรรทัด Ft', (tester) async {
    await open(tester, area: 'province');
    await tester.tap(find.text('น้ำ'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '25');
    await tester.pump();

    expect(find.text('${money.format(EnergyCalculator.calculateWater(25, 'province'))} บาท'), findsOneWidget);
    expect(find.text('ค่า Ft'), findsNothing);
  });

  test('ยอดแยกส่วนรวมกันเท่ายอดรวมทุกสูตร', () {
    for (final p in [
      TariffTables.electricityParts(437.5, ftRate: ft),
      TariffTables.electricityParts(88, ftRate: ft, small: true),
      TariffTables.electricityTouParts(120, 340, ftRate: ft),
      TariffTables.waterMwaParts(42),
      TariffTables.waterPwaParts(63),
    ]) {
      expect(p.energy + p.ft + p.service + p.rawWater + p.vat, closeTo(p.total, 1e-9));
    }
  });
}
