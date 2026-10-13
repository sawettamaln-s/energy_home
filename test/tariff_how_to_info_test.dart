// เทสหน้าต่าง "ดูประเภทอัตราค่าไฟยังไง?" (showTariffHowToInfo ใน settings_tariff.dart)
// ต้องบอกวิธีดูขนาดมิเตอร์จากหน้าปัด และรหัสประเภทตามการไฟฟ้าของพื้นที่
import 'package:energy_home/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openInfo(WidgetTester tester, String area) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showTariffHowToInfo(context, area),
            child: const Text('เปิด'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();
  }

  testWidgets('กทม. -> บอกหน้าปัด 5(15)A / 15(45)A และรหัส 1.1 / 1.2', (tester) async {
    await openInfo(tester, 'bangkok');
    expect(find.textContaining('5(15)A = มิเตอร์ 5 แอมแปร์'), findsOneWidget);
    expect(find.textContaining('15(45)A หรือใหญ่กว่า = มิเตอร์ใหญ่กว่า 5 แอมแปร์'), findsOneWidget);
    expect(find.textContaining('เป็นประเภท 1.2 เสมอ'), findsOneWidget);
  });

  testWidgets('ภูมิภาค -> ใช้รหัสของ กฟภ. (1.1.2)', (tester) async {
    await openInfo(tester, 'province');
    expect(find.textContaining('เป็นประเภท 1.1.2 เสมอ'), findsOneWidget);
  });
}
