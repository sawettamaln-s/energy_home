// เทส AppBottomNavBar (lib/widgets/app_bottom_nav_bar.dart) — บาร์ล่างแบบ
// floating pill ที่ใช้ร่วมกันทุกหน้าหลัก (หน้าหลัก/วิเคราะห์/อุปกรณ์/ตั้งค่า)
//
// หมายเหตุสำคัญ: เทสนี้ตั้งใจ "ต้องส่ง onTap เสมอ" เพราะถ้าไม่ส่ง onTap
// widget จะ fallback ไปใช้ Navigator.pushReplacement ไปหน้าจริง
// (DashboardScreen/AnalysisScreen/ฯลฯ) ซึ่งหน้าพวกนั้นเรียก
// FirebaseAuth.instance/FirestoreService() ตรงๆ ใน initState() แล้วจะพัง
// ทันทีในสภาพแวดล้อมเทสที่ไม่มี Firebase.initializeApp() — พฤติกรรม fallback
// path นี้เลยไม่ได้อยู่ในขอบเขตของเทสชุดนี้ (ดู comment เดียวกันใน
// test/widget_test.dart เรื่อง MainShell branch ที่ยังเทสเต็มรูปแบบไม่ได้)
//
// ครอบเฉพาะ path หลัก (มาจาก MainShell เสมอในการใช้งานจริง):
//   1) แตะแท็บอื่น -> เรียก onTap พร้อม index ที่ถูกต้อง
//   2) แตะแท็บที่ selected อยู่แล้ว -> ไม่เรียก onTap ซ้ำ (ดูโค้ด
//      `if (index == currentIndex) return;`)
//   3) แสดงครบทั้ง 4 แท็บพร้อม label ที่ถูกต้อง
import 'package:energy_home/widgets/app_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildNavBar(int currentIndex, ValueChanged<int> onTap) {
    return MaterialApp(
      home: Scaffold(
        body: AppBottomNavBar(currentIndex: currentIndex, onTap: onTap),
      ),
    );
  }

  testWidgets('แสดงครบทั้ง 4 แท็บพร้อม label ที่ถูกต้อง', (tester) async {
    await tester.pumpWidget(buildNavBar(0, (_) {}));

    expect(find.text('หน้าหลัก'), findsOneWidget);
    expect(find.text('วิเคราะห์'), findsOneWidget);
    expect(find.text('อุปกรณ์'), findsOneWidget);
    expect(find.text('ตั้งค่า'), findsOneWidget);
  });

  testWidgets('แตะแท็บ "วิเคราะห์" (index 1) ขณะอยู่แท็บหน้าหลัก -> onTap(1)',
      (tester) async {
    int? tappedIndex;
    await tester.pumpWidget(buildNavBar(0, (i) => tappedIndex = i));

    await tester.tap(find.text('วิเคราะห์'));
    await tester.pump();

    expect(tappedIndex, 1);
  });

  testWidgets('แตะแท็บที่ selected อยู่แล้ว -> ไม่เรียก onTap ซ้ำ',
      (tester) async {
    var callCount = 0;
    await tester.pumpWidget(buildNavBar(2, (_) => callCount++));

    await tester.tap(find.text('อุปกรณ์')); // index 2 = แท็บปัจจุบันอยู่แล้ว
    await tester.pump();

    expect(callCount, 0);
  });

  testWidgets('แตะแท็บ "ตั้งค่า" (index 3) -> onTap(3)', (tester) async {
    int? tappedIndex;
    await tester.pumpWidget(buildNavBar(0, (i) => tappedIndex = i));

    await tester.tap(find.text('ตั้งค่า'));
    await tester.pump();

    expect(tappedIndex, 3);
  });
}