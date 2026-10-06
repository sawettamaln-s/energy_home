// เทสหน้าแจ้งเตือน (lib/screens/dashboard/notification_screen.dart):
// แตะแจ้งเตือนค่าใช้จ่ายพุ่ง/คาดการณ์สูงขึ้นแล้วพาไปแท็บวิเคราะห์ และการยกเลิก
// เตือนวันตัดรอบตอนออกจากระบบ (NotificationService.cancelScheduledForSignOut)
import 'package:energy_home/screens/dashboard/notification_screen.dart';
import 'package:energy_home/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final service = NotificationService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.uidProvider = () => 'user-1';
  });

  Future<List<int>> openAndTap(WidgetTester tester, String text) async {
    final opened = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    NotificationScreen(onOpenAnalysis: () => opened.add(1)),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(text));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('แตะแจ้งเตือนค่าใช้จ่ายพุ่ง -> ปิดหน้าแจ้งเตือนแล้วไปแท็บวิเคราะห์',
      (tester) async {
    await service.checkUsageSpike(
      currentElectricityCost: 1400,
      lastMonthElectricityCost: 1000,
      currentWaterCost: 0,
      lastMonthWaterCost: 0,
      cycleStart: DateTime(2026, 6, 1),
      silent: true,
    );
    final opened = await openAndTap(tester, 'ค่าไฟรอบบิลนี้เกินบิลก่อนแล้วค่ะ');
    expect(opened, [1]);
    expect(find.byType(NotificationScreen), findsNothing);
  });

  testWidgets('แตะแจ้งเตือนคาดการณ์สิ้นรอบสูงขึ้น -> ไปแท็บวิเคราะห์', (tester) async {
    await service.checkForecastHigherThanLastMonth(
      forecastTotal: 1300,
      lastMonthTotal: 1000,
      cycleStart: DateTime(2026, 6, 1),
      silent: true,
    );
    final opened = await openAndTap(tester, 'แนวโน้มค่าใช้จ่ายรอบนี้สูงขึ้น');
    expect(opened, [1]);
  });

  test('ออกจากระบบ -> ล้างกำหนดการเตือนวันตัดรอบของบัญชีนี้ ไม่ throw', () async {
    SharedPreferences.setMockInitialValues(
        {'user-1_pending_billing_reminder_time': '2026-07-01T09:00:00.000'});
    await service.cancelScheduledForSignOut();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user-1_pending_billing_reminder_time'), isNull);
  });
}
