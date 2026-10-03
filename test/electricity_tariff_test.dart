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

BillModel _bill(int year, int month, double used) => BillModel(
      id: 'b_${year}_$month',
      uid: 'u',
      year: year,
      month: month,
      electricityUsed: used,
      electricityCost: used * 4,
    );

void main() {
  group('สูตรค่าไฟตามประเภทอัตรา', () {
    test('ประเภท 1.1.1: ขั้นบันได 7 ขั้น + ค่าบริการ 8.19', () async {
      final ft = await EnergyCalculator.getFtRate();
      // 100 หน่วย = 15x2.3488 + 10x2.9882 + 10x3.2405 + 65x3.6237
      const energy = 15 * 2.3488 + 10 * 2.9882 + 10 * 3.2405 + 65 * 3.6237;
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
}
