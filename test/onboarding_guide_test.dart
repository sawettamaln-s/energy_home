// เทสคู่มือเริ่มต้นใช้งาน (lib/widgets/onboarding_guide.dart): หน้าตั้งค่า 3 ขั้นตอนมี
// หมายเหตุประเภทอัตราค่าไฟตามรหัสของการไฟฟ้าในพื้นที่ (ไม่แสดงกับมิเตอร์ TOU)
// และแสดงแค่ครั้งแรก
import 'package:energy_home/widgets/onboarding_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openGuide(WidgetTester tester, {String? area, String? meterType}) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => OnboardingGuide.showIfFirstTime(context, area: area, meterType: meterType),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // ไปหน้า "ตั้งค่าเริ่มต้น 3 ขั้นตอน"
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
  }

  testWidgets('กฟน. มิเตอร์ปกติ -> หมายเหตุใช้รหัส 1.2 / 1.1', (tester) async {
    await openGuide(tester, area: 'bangkok', meterType: 'normal');
    expect(find.textContaining('ไว้ที่ 1.2 ของบ้านส่วนใหญ่'), findsOneWidget);
    expect(find.textContaining('ระบุ 1.1 (มิเตอร์ไม่เกิน 5 แอมแปร์)'), findsOneWidget);
  });

  testWidgets('กฟภ. มิเตอร์ปกติ -> หมายเหตุใช้รหัส 1.1.2 / 1.1.1', (tester) async {
    await openGuide(tester, area: 'province', meterType: 'normal');
    expect(find.textContaining('ไว้ที่ 1.1.2 ของบ้านส่วนใหญ่'), findsOneWidget);
    expect(find.textContaining('ระบุ 1.1.1 (มิเตอร์ไม่เกิน 5 แอมแปร์)'), findsOneWidget);
  });

  testWidgets('มิเตอร์ TOU -> ไม่มีหมายเหตุประเภทอัตรา', (tester) async {
    await openGuide(tester, area: 'bangkok', meterType: 'tou');
    expect(find.textContaining('ตรวจเพิ่มเติม'), findsNothing);
    expect(find.text('ตั้งค่าเริ่มต้น 3 ขั้นตอน'), findsOneWidget);
  });

  testWidgets('เคยเห็นแล้ว -> ไม่แสดงซ้ำ', (tester) async {
    SharedPreferences.setMockInitialValues({'has_seen_onboarding_guide': true});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => OnboardingGuide.showIfFirstTime(context, area: 'bangkok', meterType: 'normal'),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('ถัดไป'), findsNothing);
  });
}
