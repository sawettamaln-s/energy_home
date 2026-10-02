// เทสเงื่อนไขของระบบแจ้งเตือน (lib/services/notification_service.dart):
// สวิตช์เปิด/ปิดรายประเภทในหน้าตั้งค่ามีผลจริง, เกณฑ์ที่ใช้ตัดสินว่าจะเตือน
// ไหม และการกันแจ้งเตือนซ้ำ (ต่อวัน / ต่อรอบบิล / ต่อบิล / ต่อเดือนที่ขาด)
//
// ทุกเคสเรียกแบบ silent: true — บันทึกลงประวัติแต่ไม่ยิงแจ้งเตือนจริงผ่าน
// plugin (ซึ่งต้องรันบนเครื่องจริง) จึงตรวจผลได้จากประวัติแจ้งเตือนในเครื่อง
// ส่วนการตั้งเวลาเตือนใกล้วันตัดรอบ (zonedSchedule) ต้องทดสอบบนเครื่องจริง
import 'package:energy_home/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final service = NotificationService.instance;
  final cycleStart = DateTime(2026, 6, 30);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.uidProvider = () => 'user-1';
  });

  Future<List<String>> historyTypes() async =>
      (await service.getHistory()).map((e) => e.type).toList();

  group('สวิตช์เปิด/ปิดรายประเภท', () {
    test('ค่าเริ่มต้นเปิดทุกประเภท', () async {
      final prefs = await service.getAllTypePreferences();
      expect(prefs.values, everyElement(isTrue));
      expect(prefs.keys, containsAll(['billing', 'meter', 'spike', 'summary']));
    });

    test('ปิด "meter" -> ไม่เตือนยังไม่บันทึกมิเตอร์ และไม่เตือนรอบที่ขาด', () async {
      await service.setTypeEnabled('meter', false);
      await service.checkMeterNotRecorded(
          lastLogDate: DateTime.now().subtract(const Duration(days: 10)),
          silent: true);
      await service.notifyMissedCycles(months: ['5/2026'], silent: true);
      expect(await historyTypes(), isEmpty);
    });

    test('ปิด "spike" -> ไม่เตือนค่าใช้จ่ายพุ่ง และไม่เตือนแนวโน้มสูงขึ้น', () async {
      await service.setTypeEnabled('spike', false);
      await service.checkUsageSpike(
        currentElectricityCost: 2000,
        lastMonthElectricityCost: 1000,
        currentWaterCost: 0,
        lastMonthWaterCost: 0,
        cycleStart: cycleStart,
        silent: true,
      );
      await service.checkForecastHigherThanLastMonth(
          forecastTotal: 2000,
          lastMonthTotal: 1000,
          cycleStart: cycleStart,
          silent: true);
      expect(await historyTypes(), isEmpty);
    });

    test('ปิด "summary" -> ไม่สรุปยอดท้ายรอบ', () async {
      await service.setTypeEnabled('summary', false);
      await service.notifyCycleSummary(
          billId: 'b1', totalCost: 1500, year: 2026, month: 7, silent: true);
      expect(await historyTypes(), isEmpty);
    });

    test('สวิตช์แยกตามบัญชี — ปิดในบัญชีหนึ่งไม่กระทบอีกบัญชี', () async {
      await service.setTypeEnabled('meter', false);
      service.uidProvider = () => 'user-2';
      expect(await service.isTypeEnabled('meter'), isTrue);
    });
  });

  group('เตือนยังไม่บันทึกมิเตอร์', () {
    test('ไม่ได้บันทึก 5 วันขึ้นไป -> เตือน วันละครั้งเท่านั้น', () async {
      final lastLog = DateTime.now().subtract(const Duration(days: 6));
      await service.checkMeterNotRecorded(lastLogDate: lastLog, silent: true);
      await service.checkMeterNotRecorded(lastLogDate: lastLog, silent: true);
      expect(await historyTypes(), ['meter']);
    });

    test('เพิ่งบันทึกเมื่อ 3 วันก่อน -> ไม่เตือน', () async {
      await service.checkMeterNotRecorded(
          lastLogDate: DateTime.now().subtract(const Duration(days: 3)),
          silent: true);
      expect(await historyTypes(), isEmpty);
    });
  });

  group('เตือนค่าใช้จ่ายพุ่งขึ้น (เทียบบิลเดือนก่อน)', () {
    Future<void> check(double current, double lastMonth) =>
        service.checkUsageSpike(
          currentElectricityCost: current,
          lastMonthElectricityCost: lastMonth,
          currentWaterCost: 0,
          lastMonthWaterCost: 0,
          cycleStart: cycleStart,
          silent: true,
        );

    test('สูงกว่าเดือนก่อน 40% -> เตือน และเตือนครั้งเดียวต่อรอบบิล', () async {
      await check(1400, 1000);
      await check(1500, 1000);
      expect(await historyTypes(), ['spike']);
    });

    test('สูงกว่าเดือนก่อนแค่ 20% (ต่ำกว่าเกณฑ์ 30%) -> ไม่เตือน', () async {
      await check(1200, 1000);
      expect(await historyTypes(), isEmpty);
    });

    test('ไม่มีบิลเดือนก่อน (0) -> ไม่เตือน', () async {
      await check(1200, 0);
      expect(await historyTypes(), isEmpty);
    });
  });

  group('เตือนแนวโน้มคาดการณ์สิ้นรอบสูงกว่าเดือนก่อน', () {
    test('สูงกว่า 15% ขึ้นไป -> เตือนประเภท forecast ครั้งเดียวต่อรอบ', () async {
      for (var i = 0; i < 2; i++) {
        await service.checkForecastHigherThanLastMonth(
            forecastTotal: 1200,
            lastMonthTotal: 1000,
            cycleStart: cycleStart,
            silent: true);
      }
      expect(await historyTypes(), ['forecast']);
    });

    test('สูงกว่าแค่ 10% -> ไม่เตือน', () async {
      await service.checkForecastHigherThanLastMonth(
          forecastTotal: 1100,
          lastMonthTotal: 1000,
          cycleStart: cycleStart,
          silent: true);
      expect(await historyTypes(), isEmpty);
    });
  });

  group('สรุปยอดท้ายรอบ และรอบบิลที่ไม่มีข้อมูล', () {
    test('สรุปยอดบิลเดียวกันครั้งเดียว บิลใหม่สรุปได้อีก', () async {
      await service.notifyCycleSummary(
          billId: 'b1', totalCost: 1500, year: 2026, month: 7, silent: true);
      await service.notifyCycleSummary(
          billId: 'b1', totalCost: 1500, year: 2026, month: 7, silent: true);
      await service.notifyCycleSummary(
          billId: 'b2', totalCost: 1600, year: 2026, month: 8, silent: true);
      expect(await historyTypes(), ['summary', 'summary']);
    });

    test('เดือนที่ขาดแจ้งครั้งเดียวต่อเดือน และจำไว้ให้แดชบอร์ดข้าม', () async {
      await service.notifyMissedCycles(months: ['5/2026'], silent: true);
      await service.notifyMissedCycles(months: ['5/2026'], silent: true);
      await service.notifyMissedCycles(
          months: ['5/2026', '6/2026'], silent: true);

      final history = await service.getHistory();
      expect(history.map((e) => e.type), ['missed_cycle', 'missed_cycle']);
      expect(history.first.body, contains('6/2026'));
      expect(history.first.body, isNot(contains('5/2026')));
      expect(await service.isCycleFlaggedMissing('5/2026'), isTrue);
    });
  });

  group('ประวัติและ badge ยังไม่อ่าน', () {
    test('อ่านแล้ว/อ่านทั้งหมด/ลบ ปรับจำนวนยังไม่อ่านถูกต้อง', () async {
      await service.notifyCycleSummary(
          billId: 'b1', totalCost: 1, year: 2026, month: 7, silent: true);
      await service.notifyCycleSummary(
          billId: 'b2', totalCost: 1, year: 2026, month: 8, silent: true);
      expect(await service.getUnreadCount(), 2);

      final first = (await service.getHistory()).first;
      await service.markAsRead(first.id);
      expect(await service.getUnreadCount(), 1);

      await service.markAllAsRead();
      expect(await service.getUnreadCount(), 0);

      await service.deleteOne(first.id);
      expect(await service.getHistory(), hasLength(1));

      await service.clearHistory();
      expect(await service.getHistory(), isEmpty);
    });
  });
}
