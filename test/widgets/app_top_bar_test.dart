// เทส AppTopBar (lib/widgets/app_top_bar.dart) — แถบด้านบนมาตรฐานที่ใช้ร่วม
// กันเกือบทุกหน้าของแอป เป็น StatelessWidget ล้วนๆ ไม่พึ่ง Firebase เลย
// จึงเทสได้ตรงๆ โดยไม่ต้อง mock อะไร
//
// ครอบกติกาหลักที่คอมเมนต์ในไฟล์เดิมล็อกไว้:
//   1) title แสดงกึ่งกลาง (centerTitle) และห่อด้วย FittedBox ป้องกันชื่อยาว
//      ล้นแทนการตัดจบด้วย "..."
//   2) showBack: true (ค่า default) ต้องเห็นปุ่มย้อนกลับ (chevron_left)
//      และกดแล้ว pop ออกจากหน้าปัจจุบันได้จริง
//   3) showBack: false ต้องไม่มีปุ่มย้อนกลับเลย (หน้าหลักที่เข้าถึงผ่าน
//      bottom nav โดยตรง ไม่มีหน้าให้ pop กลับไป)
//   4) ส่ง actions/backgroundColor เองได้ ค่าที่ส่งต้องถูกนำไปใช้จริง
import 'package:energy_home/screens/dashboard/dashboard_styles.dart';
import 'package:energy_home/widgets/app_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapWithNavigator(PreferredSizeWidget appBar) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          appBar: appBar,
          body: Center(
            child: ElevatedButton(
              // หน้าแรกก่อน push AppTopBar เข้าไป เพื่อให้ปุ่มย้อนกลับมีที่ให้ pop จริง
              onPressed: () {},
              child: const Text('base'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('แสดง title ตรงกลาง', (tester) async {
    await tester.pumpWidget(wrapWithNavigator(
      const AppTopBar(title: 'หน้าตั้งค่า'),
    ));

    expect(find.text('หน้าตั้งค่า'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.centerTitle, isTrue);
  });

  testWidgets('showBack: true (ค่า default) -> เห็นปุ่มย้อนกลับแบบ chevron',
      (tester) async {
    await tester.pumpWidget(wrapWithNavigator(
      const AppTopBar(title: 'รายละเอียด'),
    ));

    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('showBack: false -> ไม่มีปุ่มย้อนกลับเลย', (tester) async {
    await tester.pumpWidget(wrapWithNavigator(
      const AppTopBar(title: 'หน้าหลัก', showBack: false),
    ));

    expect(find.byIcon(Icons.chevron_left), findsNothing);
  });

  testWidgets('กดปุ่มย้อนกลับ -> pop ออกจากหน้าปัจจุบันจริง', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const Scaffold(
                    appBar: AppTopBar(title: 'หน้าย่อย'),
                    body: SizedBox(),
                  ),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('หน้าย่อย'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(find.text('หน้าย่อย'), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('ใช้ backgroundColor ที่ส่งมาเอง ไม่ fallback ไป primaryGreen',
      (tester) async {
    await tester.pumpWidget(wrapWithNavigator(
      const AppTopBar(title: 'พิเศษ', backgroundColor: Colors.deepPurple),
    ));

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.deepPurple);
  });

  testWidgets('ไม่ส่ง backgroundColor -> ใช้ primaryGreen เป็นค่า default',
      (tester) async {
    await tester.pumpWidget(wrapWithNavigator(
      const AppTopBar(title: 'ปกติ'),
    ));

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, DashboardStyles.primaryGreen);
  });

  testWidgets('actions ที่ส่งมาแสดงจริงใน AppBar', (tester) async {
    await tester.pumpWidget(wrapWithNavigator(
      AppTopBar(
        title: 'มีปุ่มเสริม',
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
        ],
      ),
    ));

    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}
