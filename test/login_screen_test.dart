// เทส LoginScreen (login ด้วยอีเมล/รหัสผ่าน) แบบไม่ต้องพึ่ง Android emulator
// หรือ Firebase Auth ของจริงเลย — ใช้ MockFirebaseAuth (firebase_auth_mocks)
// ฉีดเข้า LoginScreen ผ่าน constructor param `auth` (ดู lib/screens/auth/
// login_screen.dart — pattern เดียวกับที่ AuthGate ใช้อยู่แล้วใน widget_test.dart)
//
// ครอบ 3 เคสหลักของฟอร์ม login:
//   1) กรอกอีเมล/รหัสผ่านถูกต้อง -> login สำเร็จ, pop กลับไปหน้าก่อนหน้า
//   2) รหัสผ่านผิด (FirebaseAuthException code: wrong-password) -> ต้องเห็น
//      ข้อความ error ภาษาไทยที่ถูกต้อง และยังค้างอยู่หน้า Login (ไม่ pop)
//   3) ไม่พบบัญชี (code: user-not-found) -> ข้อความ error อีกแบบ
//
// mock exception ใช้ whenCalling(...).on(...).thenThrow(...) จากแพ็กเกจ
// mock_exceptions (firebase_auth_mocks เวอร์ชัน >= 0.10.0 เปลี่ยนมาใช้ pattern
// นี้แทน AuthExceptions เดิม ดู CHANGELOG ของ firebase_auth_mocks)
import 'package:energy_home/screens/auth/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

void main() {
  // ห่อ LoginScreen ด้วย route แรกที่มีปุ่ม "go" ให้กดเปิด LoginScreen ขึ้นมา
  // เหมือนสถานการณ์จริง (ถูก push มาจากหน้า Welcome) เพื่อเทสพฤติกรรม pop
  // กลับตอน login สำเร็จได้ตรงกับของจริง (ดู _login() ใน login_screen.dart)
  Future<void> pumpLoginScreen(WidgetTester tester, FirebaseAuth auth) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => LoginScreen(auth: auth)),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'login สำเร็จ (อีเมล/รหัสผ่านถูกต้อง) -> pop กลับไปหน้าก่อนหน้าทันที',
      (tester) async {
    final auth = MockFirebaseAuth(signedIn: false);
    await pumpLoginScreen(tester, auth);

    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(
        find.byType(TextField).at(0), 'test@example.com'); // ช่องอีเมล
    await tester.enterText(find.byType(TextField).at(1), 'password123'); // ช่องรหัสผ่าน
    await tester.tap(find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();

    // pop กลับมาที่หน้าแรก (มีปุ่ม "go") แล้ว ไม่ใช่ LoginScreen อีกต่อไป
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('รหัสผ่านผิด -> โชว์ข้อความ error ที่ถูกต้อง และไม่ pop ออกจากหน้า',
      (tester) async {
    final auth = MockFirebaseAuth(signedIn: false);
    whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
        .on(auth)
        .thenThrow(FirebaseAuthException(code: 'wrong-password'));

    await pumpLoginScreen(tester, auth);

    await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrong-password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();

    expect(find.text('รหัสผ่านไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง'), findsOneWidget);
    // ยังอยู่หน้า Login เหมือนเดิม ไม่ได้ pop ออกไปไหน
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('ไม่พบบัญชีผู้ใช้ -> โชว์ข้อความ error ที่ถูกต้อง', (tester) async {
    final auth = MockFirebaseAuth(signedIn: false);
    whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
        .on(auth)
        .thenThrow(FirebaseAuthException(code: 'user-not-found'));

    await pumpLoginScreen(tester, auth);

    await tester.enterText(
        find.byType(TextField).at(0), 'ghost@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();

    expect(
      find.text('ไม่พบบัญชีผู้ใช้นี้ในระบบ กรุณาตรวจสอบอีเมลของคุณอีกครั้ง'),
      findsOneWidget,
    );
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}