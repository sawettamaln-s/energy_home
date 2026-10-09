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

  // กดแถว (เขต/มิเตอร์/อัตรา) แล้วเลือกค่าจากรายการที่เด้งขึ้น
  Future<void> pick(WidgetTester tester, String row, String option) async {
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('เปลี่ยนเขต/มิเตอร์/ประเภทอัตราในชีต -> คิดตามที่เลือก และกลับไปใช้ค่าของบ้านคุณได้', (tester) async {
    await open(tester);
    expect(find.text('คิดตามอัตราของบ้านคุณ'), findsOneWidget);
    expect(find.text('กทม.–ปริมณฑล (กฟน.)'), findsOneWidget);
    expect(find.text('เกิน 150 หน่วย'), findsOneWidget);

    await pick(tester, 'เขต', 'ต่างจังหวัด');
    await pick(tester, 'อัตรา', 'ไม่เกิน 150 หน่วย');
    await tester.enterText(find.byType(TextField), '120');
    await tester.pump();

    final total = EnergyCalculator.electricityCost(120, ftRate: ft, tariff: EnergyCalculator.tariffSmall);
    expect(find.text('${money.format(total)} บาท'), findsOneWidget);
    expect(find.textContaining('อัตราประเภท 1.1.1 ของการไฟฟ้าส่วนภูมิภาค'), findsOneWidget);
    expect(find.text('คิดให้บ้านอื่น'), findsOneWidget);
    expect(find.text('ต่างจังหวัด (กฟภ.)'), findsOneWidget);
    expect(find.text('ไม่เกิน 150 หน่วย'), findsOneWidget);

    await pick(tester, 'มิเตอร์', 'มิเตอร์ TOU');
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('อัตรา'), findsNothing, reason: 'TOU ไม่มีประเภทอัตรา ≤150/>150');

    await tester.tap(find.text('ใช้ค่าของบ้านคุณ'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('คิดตามอัตราของบ้านคุณ'), findsOneWidget);
    expect(find.textContaining('อัตราประเภท 1.2 ของการไฟฟ้านครหลวง'), findsOneWidget);
  });

  testWidgets('น้ำ -> มีแค่ตัวเลือกเขต (กปน./กปภ.)', (tester) async {
    await open(tester);
    await tester.tap(find.text('น้ำ'));
    await tester.pump();
    expect(find.text('กทม.–ปริมณฑล (กปน.)'), findsOneWidget);
    expect(find.text('มิเตอร์'), findsNothing);
    expect(find.text('อัตรา'), findsNothing);

    await pick(tester, 'เขต', 'ต่างจังหวัด');
    expect(find.text('ต่างจังหวัด (กปภ.)'), findsOneWidget);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '25');
    await tester.pump();
    expect(find.text('${money.format(EnergyCalculator.calculateWater(25, 'province'))} บาท'), findsOneWidget);
  });

  testWidgets('กรอกยอดเงิน -> หน่วยเต็มที่มากที่สุดที่ยอดไม่เกิน', (tester) async {
    await open(tester);
    await tester.tap(find.text('คิดจากยอดเงิน'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '1000');
    await tester.pump();

    double cost(double u) => TariffTables.electricityParts(u, ftRate: ft).total;
    final units = TariffTables.unitsForBudget(1000, cost)!;
    expect(cost(units.toDouble()), lessThanOrEqualTo(1000));
    expect(cost(units + 1.0), greaterThan(1000));
    expect(find.text('$units หน่วย'), findsOneWidget);
    // ยอดที่กรอกอยู่ระหว่างยอดของหน่วยที่ได้ (ไม่เกิน) กับหน่วยถัดไป (เกิน)
    expect(find.text('$units หน่วย (ไม่เกินยอดที่กรอก)'), findsOneWidget);
    expect(find.text('${money.format(cost(units.toDouble()))} บาท'), findsOneWidget);
    expect(find.text('${units + 1} หน่วย (เกินยอดที่กรอก)'), findsOneWidget);
    expect(find.text('${money.format(cost(units + 1.0))} บาท'), findsOneWidget);
  });

  testWidgets('กรอกยอดเงิน TOU -> บอกเป็นช่วงตั้งแต่ On-Peak ทั้งหมดถึง Off-Peak ทั้งหมด', (tester) async {
    await open(tester, meterType: 'tou');
    await tester.tap(find.text('คิดจากยอดเงิน'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '1500');
    await tester.pump();

    final peak = TariffTables.unitsForBudget(
        1500, (u) => TariffTables.electricityTouParts(u, 0, ftRate: ft).total)!;
    final offPeak = TariffTables.unitsForBudget(
        1500, (u) => TariffTables.electricityTouParts(0, u, ftRate: ft).total)!;
    expect(peak, lessThan(offPeak));
    expect(find.text('$peak–$offPeak หน่วย'), findsOneWidget);
  });

  testWidgets('กรอกยอดเงินน้อยกว่าค่าบริการ -> บอกยอดขั้นต่ำ', (tester) async {
    await open(tester);
    await tester.tap(find.text('คิดจากยอดเงิน'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();

    expect(find.textContaining('ยอดนี้น้อยกว่าค่าบริการรายเดือนรวม VAT'), findsOneWidget);
  });

  testWidgets('ปุ่ม i อธิบายการทำงานของเครื่องคิด', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('เครื่องคิดนี้ทำงานอย่างไร'));
    await tester.pumpAndSettle();
    expect(find.text('เครื่องคิดนี้ทำงานอย่างไร?'), findsOneWidget);
    expect(find.text('ทำไมยอดไม่ตรงกับที่กรอกพอดี'), findsOneWidget);
  });

  test('unitsForBudget: น้ำ กปน./กปภ. หาหน่วยเต็มที่ยอดไม่เกินงบ', () {
    for (final cost in [TariffTables.waterMwaCost, TariffTables.waterPwaCost]) {
      for (final budget in [50.0, 300.0, 2500.0]) {
        final units = TariffTables.unitsForBudget(budget, cost);
        if (units == null) {
          expect(cost(0), greaterThan(budget));
          continue;
        }
        expect(cost(units.toDouble()), lessThanOrEqualTo(budget));
        expect(cost(units + 1.0), greaterThan(budget));
      }
    }
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
