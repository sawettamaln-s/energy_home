// เทสงานข้อมูลของหน้าหลัก (lib/screens/dashboard/dashboard_loader.dart):
//   - load(): ยอดใช้ไปแล้ว ยอดคาดการณ์ รายจ่ายประจำของเดือนบิล และสถานะการ์ด
//     มิเตอร์ (พร้อม/ล็อก + ข้อความ) จากข้อมูลใน Firestore
//   - runBackgroundTasks(): ปิดบิลรอบที่เพิ่งจบ แจ้งสรุปยอด และคำแนะนำประเภท
//     อัตราใหม่ (ครั้งแรกเท่านั้น)
//
// ใช้ FakeFirebaseFirestore + SharedPreferences จำลอง แจ้งเตือนเรียกแบบ
// silent จึงตรวจผลจากประวัติแจ้งเตือนในเครื่องได้ (การตั้งเวลาแจ้งเตือนผ่าน
// plugin ทำไม่ได้ในเทส ตัว loader จับ error ไว้เอง)
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/fixed_cost_item_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/dashboard/dashboard_loader.dart';
import 'package:energy_home/screens/dashboard/record_meter_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/services/notification_service.dart';
import 'package:energy_home/utils/calculator.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'u1';

void main() {
  late FirestoreService service;
  late DashboardLoader loader;
  // รอบบิลวันที่ 1: รอบปัจจุบัน 1 มิ.ย. - 1 ก.ค. 2026 วันนี้ = 11 มิ.ย.
  final now = DateTime(2026, 6, 11, 12);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    NotificationService.instance.uidProvider = () => _uid;
    service = FirestoreService(firestore: FakeFirebaseFirestore());
    loader = DashboardLoader(firestoreService: service);
  });

  Future<void> createUser({
    int startMonth = 6,
    bool startConfigured = true,
    String tariff = EnergyCalculator.tariffStandard,
  }) =>
      service.createUser(UserModel(
        uid: _uid,
        name: 'ทดสอบ',
        email: 'u1@example.com',
        billingDay: 1,
        startElectricityValue: 1000,
        startWaterValue: 100,
        startBillingMonth: startConfigured ? startMonth : 0,
        startBillingYear: startConfigured ? 2026 : 0,
        startMeterConfigured: startConfigured,
        electricityStartConfigured: startConfigured,
        waterStartConfigured: startConfigured,
        electricityTariff: tariff,
      ));

  group('load', () {
    test('ยอดใช้ไปแล้ว คาดการณ์สิ้นรอบ และรายจ่ายประจำของเดือนบิล', () async {
      await createUser();
      final costNow = await EnergyCalculator.calculateElectricity(100, 'bangkok');
      // บันทึกวันที่ 6 มิ.ย. (ผ่านไป 5 วันจากรอบ 30 วัน) → หน่วยทั้งรอบ = x6
      await service.saveElectricityLog(ElectricityLogModel(
          id: 'e1', uid: _uid, date: DateTime(2026, 6, 6),
          meterValue: 1100, usedFromStart: 100, cost: costNow));
      // รายจ่ายประจำที่ active ในเดือนบิลรอบนี้ (ก.ค.) เท่านั้น
      await service.saveFixedCostItem(FixedCostItemModel(
          id: 'f1', uid: _uid, name: 'เน็ต', category: 'internet',
          amount: 500, createdAt: DateTime(2026, 7, 1),
          startDate: DateTime(2026, 7, 1)));

      final data = await loader.load(_uid, now: now);

      expect(data.cycleStart, DateTime(2026, 6, 1));
      expect(data.cycleEnd, DateTime(2026, 7, 1));
      expect(data.currentElectricityCost, costNow);
      expect(data.currentElectricityUnits, 100);
      expect(data.hasForecastData, isTrue);
      expect(data.forecastElectricityCost,
          await EnergyCalculator.calculateElectricity(600, 'bangkok'));
      expect(data.billFixedCost, 500);
      expect(data.electricityMeterReady, isTrue);
      expect(data.waterMeterReady, isTrue);
    });

    test('เทียบยอดคาดการณ์ค่าไฟ+ค่าน้ำกับบิลล่าสุดเป็น %', () async {
      await createUser();
      final cost = await EnergyCalculator.calculateElectricity(100, 'bangkok');
      await service.saveElectricityLog(ElectricityLogModel(
          id: 'e1', uid: _uid, date: DateTime(2026, 6, 6),
          meterValue: 1100, usedFromStart: 100, cost: cost));
      final forecast = await EnergyCalculator.calculateElectricity(600, 'bangkok');
      await service.saveBill(BillModel(
          id: 'b5', uid: _uid, year: 2026, month: 6,
          electricityCost: forecast / 2, waterCost: 0));

      final data = await loader.load(_uid, now: now);
      expect(data.forecastChangeVsLastBill, closeTo(100, 0.01));
    });

    test('ยังไม่มีบิลก่อนให้เทียบ -> ไม่มีตัวเลขเทียบ', () async {
      await createUser();
      await service.saveElectricityLog(ElectricityLogModel(
          id: 'e1', uid: _uid, date: DateTime(2026, 6, 6),
          meterValue: 1100, usedFromStart: 100, cost: 400));
      final data = await loader.load(_uid, now: now);
      expect(data.hasForecastData, isTrue);
      expect(data.forecastChangeVsLastBill, isNull);
    });

    test('ยังไม่มีบันทึก -> ยังไม่คาดการณ์ ยอดเป็นศูนย์', () async {
      await createUser();
      final data = await loader.load(_uid, now: now);
      expect(data.hasForecastData, isFalse);
      expect(data.forecastTotal, 0);
      expect(data.historyFor(MeterKind.electricity), isEmpty);
    });

    test('เลขต้นรอบเป็นของรอบก่อน -> การ์ดล็อก บอกวันเริ่มรอบใหม่', () async {
      await createUser(startMonth: 5);
      final data = await loader.load(_uid, now: now);
      expect(data.electricityMeterReady, isFalse);
      expect(data.staleCycleMessage, startsWith('รอบบิลใหม่เริ่ม 1 มิถุนายน'));
    });

    test('เลขต้นรอบใหม่กว่ารอบปัจจุบัน -> บอกว่าวันตัดรอบบิลเปลี่ยน', () async {
      await createUser(startMonth: 7);
      final data = await loader.load(_uid, now: now);
      expect(data.electricityMeterReady, isFalse);
      expect(data.staleCycleMessage, startsWith('วันตัดรอบบิลเปลี่ยนแล้ว'));
    });
  });

  group('runBackgroundTasks', () {
    test('ปิดบิลรอบที่เพิ่งจบ แล้วแจ้งสรุปยอด', () async {
      await createUser(startMonth: 5);
      // log ของรอบที่แล้ว (1 พ.ค. - 1 มิ.ย.)
      await service.saveElectricityLog(ElectricityLogModel(
          id: 'old', uid: _uid, date: DateTime(2026, 5, 31, 23, 59, 30),
          meterValue: 1200, usedFromStart: 200, cost: 900));

      final data = await loader.load(_uid, now: now);
      final result = await loader.runBackgroundTasks(data, silent: true);

      final bills = await service.getBills(_uid);
      expect(bills.map((b) => b.id), contains('compiled_2026_06'));
      final history = await NotificationService.instance.getHistory();
      expect(history.map((e) => e.type), contains('summary'));
      expect(result.unreadNotifications, isNotNull);
    });

    test('บิล 3 เดือนใช้ไม่เกิน 150 หน่วย -> คำแนะนำประเภทอัตราครั้งแรกเท่านั้น',
        () async {
      await createUser();
      for (final m in [3, 4, 5]) {
        await service.saveBill(BillModel(
            id: 'b$m', uid: _uid, year: 2026, month: m,
            electricityUsed: 120, electricityCost: 500));
      }
      // บิลของรอบที่เพิ่งจบมีแล้ว ระบบจะไม่ปิดบิลซ้ำ
      await service.saveBill(BillModel(
          id: 'b6', uid: _uid, year: 2026, month: 6,
          electricityUsed: 130, electricityCost: 520));

      final data = await loader.load(_uid, now: now);
      final first = await loader.runBackgroundTasks(data, silent: true);
      final second = await loader.runBackgroundTasks(data, silent: true);

      expect(first.newTariffHint?.suggestedTariff, EnergyCalculator.tariffSmall);
      expect(second.newTariffHint, isNull);
    });
  });

  group('สัดส่วน On-Peak ของรอบนี้ (TOU)', () {
    DashboardData touData(ElectricityLogModel? log, {String meterType = 'tou'}) =>
        DashboardData(
          user: UserModel(
              uid: _uid,
              name: 'x',
              email: 'x@x.com',
              meterType: meterType,
              startPeakValue: 100,
              startOffPeakValue: 500),
          cycleStart: DateTime(2026, 6, 1),
          cycleEnd: DateTime(2026, 7, 1),
          electricityLogs: [if (log != null) log],
        );
    ElectricityLogModel log(double peak, double offPeak) => ElectricityLogModel(
        id: 'e1',
        uid: _uid,
        date: DateTime(2026, 6, 5),
        meterValue: 0,
        peakMeterValue: peak,
        offPeakMeterValue: offPeak);

    test('หน่วยที่ใช้แต่ละช่วงนับจากเลขต้นรอบ', () {
      // On-Peak ใช้ 30, Off-Peak ใช้ 90 -> 25%
      expect(touData(log(130, 590)).cyclePeakShare, closeTo(0.25, 1e-9));
    });

    test('ไม่ใช่ TOU / ยังไม่ได้จด / ยังไม่ได้ใช้ -> null', () {
      expect(touData(log(130, 590), meterType: 'normal').cyclePeakShare, isNull);
      expect(touData(null).cyclePeakShare, isNull);
      expect(touData(log(100, 500)).cyclePeakShare, isNull);
    });
  });
}
