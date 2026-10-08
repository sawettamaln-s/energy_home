// เทสประเภทอัตราค่าไฟของมิเตอร์ปกติ:
//   - สูตรประเภท 1.1.1 (EnergyCalculator) และประเภทเริ่มต้นที่ไม่เปลี่ยน
//   - คำแนะนำให้ตรวจประเภทจากบิล 3 เดือนติดกัน (TariffAdvisor)
//   - เปลี่ยนประเภทแล้วคิดเงินรอบปัจจุบันใหม่ บิลเก่าไม่เปลี่ยน สลับไป-กลับได้
//     ค่าเดิม (FirestoreService.setElectricityTariff)
//   - แจ้งเตือนคำแนะนำครั้งเดียวต่อบิล (NotificationService.notifyTariffHint)
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/services/notification_service.dart';
import 'package:energy_home/utils/calculator.dart';
import 'package:energy_home/utils/tariff_advisor.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// บิลจากใบแจ้งหนี้จริง ([source] 'compiled' = บิลที่ระบบปิดให้จากยอดประมาณ)
BillModel _bill(int year, int month, double used, {String source = 'imported'}) =>
    BillModel(
      id: 'b_${year}_$month',
      uid: 'u',
      year: year,
      month: month,
      electricityUsed: used,
      electricityCost: used * 4,
      source: source,
    );

void main() {
  group('สูตรค่าไฟตามประเภทอัตรา', () {
    test('ประเภท 1.1.1: ขั้นบันได 5 ขั้น + ค่าบริการ 8.19', () async {
      final ft = await EnergyCalculator.getFtRate();
      // 100 หน่วย = 15x2.3488 + 10x2.9882 + 75x3.0000
      const energy = 15 * 2.3488 + 10 * 2.9882 + 75 * 3.0000;
      final expected = double.parse(
          ((energy + 8.19 + 100 * ft) * 1.07).toStringAsFixed(2));
      expect(
        await EnergyCalculator.calculateElectricity(100, 'bangkok',
            tariff: EnergyCalculator.tariffSmall),
        expected,
      );
    });

    test('ใช้น้อย ประเภท 1.1.1 ถูกกว่าประเภทเริ่มต้น', () async {
      final small = await EnergyCalculator.calculateElectricity(80, 'bangkok',
          tariff: EnergyCalculator.tariffSmall);
      final standard = await EnergyCalculator.calculateElectricity(80, 'bangkok');
      expect(small, lessThan(standard));
    });

    test('TOU ไม่ใช้ประเภทอัตรา', () async {
      final a = await EnergyCalculator.calculateElectricityByType(
          units: 0, meterType: 'tou', area: 'bangkok',
          peakUnits: 50, offPeakUnits: 50,
          tariff: EnergyCalculator.tariffSmall);
      final b = await EnergyCalculator.calculateElectricityTOU(
          peakUnits: 50, offPeakUnits: 50);
      expect(a, b);
    });
  });

  group('รหัสประเภทตามการไฟฟ้า และค่า Ft', () {
    test('กฟน. 1.1 / 1.2 / TOU 1.3.2 และ กฟภ. 1.1.1 / 1.1.2 / TOU 1.2.2', () {
      const small = EnergyCalculator.tariffSmall;
      const standard = EnergyCalculator.tariffStandard;
      expect(EnergyCalculator.tariffCode(small, 'bangkok'), '1.1');
      expect(EnergyCalculator.tariffCode(standard, 'bangkok'), '1.2');
      expect(EnergyCalculator.touCode('bangkok'), '1.3.2');
      expect(EnergyCalculator.tariffCode(small, 'province'), '1.1.1');
      expect(EnergyCalculator.tariffCode(standard, 'province'), '1.1.2');
      expect(EnergyCalculator.touCode('province'), '1.2.2');
    });

    test('ค่า Ft งวดที่ตั้งไว้เกิน 4 เดือน = ยังไม่ได้อัปเดตงวดใหม่', () {
      final from = DateTime(2026, 9, 1);
      expect(EnergyCalculator.isFtOutdated(from, DateTime(2026, 12, 31)), isFalse);
      expect(EnergyCalculator.isFtOutdated(from, DateTime(2027, 1, 1)), isTrue);
      expect(EnergyCalculator.isFtOutdated(null, DateTime(2030, 1, 1)), isFalse);
    });
  });

  group('ค่าน้ำประเภทที่อยู่อาศัย (ไม่มีค่าน้ำขั้นต่ำ)', () {
    test('กปน. 1 หน่วย = (8.50 + ค่าบริการ 25 + ค่าน้ำดิบ 0.15) + VAT', () {
      expect(EnergyCalculator.calculateWater(1, 'bangkok'),
          double.parse(((8.50 + 25 + 0.15) * 1.07).toStringAsFixed(2)));
    });

    test('กปภ. 1 หน่วย = (10.20 + ค่าบริการ 30) + VAT', () {
      expect(EnergyCalculator.calculateWater(1, 'province'),
          double.parse(((10.20 + 30) * 1.07).toStringAsFixed(2)));
    });

    test('กปภ. เกิน 50 หน่วย คิดหน่วยที่ 51 ขึ้นไปด้วยอัตราประเภท 2 (ตารางหมายเลข 3)', () {
      const first50 = 10 * 10.20 + 10 * 16.00 + 10 * 19.00 + 20 * 21.20;
      expect(EnergyCalculator.calculateWater(60, 'province'),
          double.parse(((first50 + 10 * 21.60 + 30) * 1.07).toStringAsFixed(2)));
    });
  });

  group('คำแนะนำประเภทอัตรา (บิล 3 เดือนติดกัน)', () {
    TariffHint? check(List<BillModel> bills,
            {String tariff = EnergyCalculator.tariffStandard,
            String meterType = 'normal'}) =>
        TariffAdvisor.check(
            bills: bills, currentTariff: tariff, meterType: meterType);

    test('ใช้ไม่เกิน 150 หน่วย 3 เดือนติดกัน -> แนะนำ 1.1.1', () {
      final hint = check([_bill(2026, 9, 120), _bill(2026, 7, 140), _bill(2026, 8, 150)]);
      expect(hint?.suggestedTariff, EnergyCalculator.tariffSmall);
      expect(hint?.latest.month, 9);
    });

    test('บิลที่ระบบปิดให้ (ยอดประมาณ) ไม่นับ -> ไม่แนะนำ', () {
      final hint = TariffAdvisor.check(
        bills: [
          _bill(2026, 3, 120),
          _bill(2026, 4, 130),
          _bill(2026, 5, 140, source: 'compiled'),
        ],
        currentTariff: EnergyCalculator.tariffStandard,
        meterType: 'normal',
      );
      expect(hint, isNull);
    });
    test('เดือนไม่ติดกัน -> ไม่แนะนำ', () {
      expect(check([_bill(2026, 5, 100), _bill(2026, 7, 100), _bill(2026, 8, 100)]),
          isNull);
    });

    test('มีเดือนที่เกิน 150 -> ไม่แนะนำ', () {
      expect(check([_bill(2026, 6, 100), _bill(2026, 7, 200), _bill(2026, 8, 100)]),
          isNull);
    });

    test('ตั้ง 1.1.1 อยู่ และใช้เกิน 150 หน่วย 3 เดือนติดกัน -> แนะนำกลับ', () {
      final hint = check(
          [_bill(2026, 6, 160), _bill(2026, 7, 200), _bill(2026, 8, 300)],
          tariff: EnergyCalculator.tariffSmall);
      expect(hint?.suggestedTariff, EnergyCalculator.tariffStandard);
    });

    test('ตั้งประเภทที่ตรงอยู่แล้ว หรือมิเตอร์ TOU -> ไม่แนะนำ', () {
      final low = [_bill(2026, 6, 100), _bill(2026, 7, 100), _bill(2026, 8, 100)];
      expect(check(low, tariff: EnergyCalculator.tariffSmall), isNull);
      expect(check(low, meterType: 'tou'), isNull);
    });
  });

  group('เปลี่ยนประเภทอัตรา', () {
    test('คิดเงินรอบปัจจุบันใหม่ บิลเก่าไม่เปลี่ยน สลับกลับได้ค่าเดิม', () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final user = UserModel(
          uid: 'u', name: 'U', email: 'u@example.com', billingDay: 1);
      await service.createUser(user);
      final now = DateTime(2026, 6, 20);

      final originalCost =
          await EnergyCalculator.calculateElectricity(80, 'bangkok');
      // log ในรอบปัจจุบัน (1 มิ.ย. - 1 ก.ค.) และ log ของรอบที่แล้ว
      await service.saveElectricityLog(ElectricityLogModel(
          id: 'now', uid: 'u', date: DateTime(2026, 6, 10),
          meterValue: 1080, usedFromStart: 80, cost: originalCost));
      await service.saveElectricityLog(ElectricityLogModel(
          id: 'old', uid: 'u', date: DateTime(2026, 5, 10),
          meterValue: 1000, usedFromStart: 80, cost: originalCost));
      await service.saveBill(_bill(2026, 6, 80));

      Future<double> costOf(String id) async => (await firestore
              .collection('users/u/electricity_logs')
              .doc(id)
              .get())
          .data()!['cost'] as double;

      await service.setElectricityTariff(user, EnergyCalculator.tariffSmall,
          now: now);
      expect(await costOf('now'),
          await EnergyCalculator.calculateElectricity(80, 'bangkok',
              tariff: EnergyCalculator.tariffSmall));
      expect(await costOf('old'), originalCost);
      expect((await service.getBills('u')).single.electricityCost, 320);
      expect((await service.getUser('u'))!.electricityTariff,
          EnergyCalculator.tariffSmall);

      await service.setElectricityTariff(
          (await service.getUser('u'))!, EnergyCalculator.tariffStandard,
          now: now);
      expect(await costOf('now'), originalCost);
    });
  });

  group('แจ้งเตือนแนะนำประเภทอัตรา', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NotificationService.instance.uidProvider = () => 'user-1';
    });

    final hint = TariffHint(EnergyCalculator.tariffSmall,
        [_bill(2026, 6, 100), _bill(2026, 7, 100), _bill(2026, 8, 100)]);

    test('คำแนะนำใหม่ครั้งแรกเท่านั้น (ใช้แสดง popup) และแจ้งเตือนครั้งเดียว',
        () async {
      final service = NotificationService.instance;
      expect(await service.notifyTariffHint(hint: hint, silent: true), isTrue);
      expect(await service.notifyTariffHint(hint: hint, silent: true), isFalse);
      expect((await service.getHistory()).map((e) => e.type), ['summary']);
    });

    test('ปิดสวิตช์สรุปยอด -> ไม่มีแจ้งเตือนในเครื่อง แต่ยังนับเป็นคำแนะนำใหม่',
        () async {
      final service = NotificationService.instance;
      await service.setTypeEnabled('summary', false);
      expect(await service.notifyTariffHint(hint: hint, silent: true), isTrue);
      expect(await service.getHistory(), isEmpty);
    });
  });

  test('ใช้ 0 หน่วย -> ยังเสียค่าบริการรายเดือน + VAT เหมือนใบแจ้งหนี้จริง', () async {
    expect(await EnergyCalculator.calculateElectricity(0, 'bangkok'), 26.34);
    expect(
        await EnergyCalculator.calculateElectricity(0, 'bangkok',
            tariff: EnergyCalculator.tariffSmall),
        8.76);
    expect(
        await EnergyCalculator.calculateElectricityTOU(
            peakUnits: 0, offPeakUnits: 0),
        26.34);
    expect(EnergyCalculator.calculateWater(0, 'bangkok'), 26.75);
    expect(EnergyCalculator.calculateWater(0, 'province'), 32.1);
  });

  group('ค่า Ft ที่ใช้คิดเงิน', () {
    tearDown(EnergyCalculator.resetFtSource);

    test('อ่านครั้งเดียวแล้วจำไว้ คิดหลายยอดไม่อ่านซ้ำ', () async {
      var reads = 0;
      EnergyCalculator.ftDocLoader = () async {
        reads++;
        return {'ft_rate': 0.4};
      };
      final a = await EnergyCalculator.calculateElectricity(100, 'bangkok');
      final b = await EnergyCalculator.calculateElectricity(200, 'bangkok');
      expect(reads, 1);
      expect(a, EnergyCalculator.electricityCost(100, ftRate: 0.4));
      expect(b, EnergyCalculator.electricityCost(200, ftRate: 0.4));
    });

    test('อ่านไม่สำเร็จ -> ใช้ค่า default และไม่จำ ครั้งหน้าลองอ่านใหม่', () async {
      var reads = 0;
      EnergyCalculator.ftDocLoader = () async {
        reads++;
        if (reads == 1) throw Exception('offline');
        return {'ft_rate': 0.4};
      };
      expect(await EnergyCalculator.getFtRate(), EnergyCalculator.defaultFtRate);
      expect(await EnergyCalculator.getFtRate(), 0.4);
    });

    test('ค่าที่อ่านจากที่อื่น (rememberFtInfo) ใช้ทันที', () async {
      EnergyCalculator.ftDocLoader = () async => {'ft_rate': 0.4};
      EnergyCalculator.rememberFtInfo((rate: 0.25, effectiveFrom: null));
      expect(await EnergyCalculator.getFtRate(), 0.25);
    });
  });
}
