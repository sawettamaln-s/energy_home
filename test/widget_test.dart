// เดิมไฟล์นี้เป็นเทส counter app ตัวอย่างจาก `flutter create` ที่ไม่มีใครแก้
// ตั้งแต่ตั้งโปรเจกต์ — พอ pump MyApp() จริง มันไปเจอ AuthGate ที่เรียก
// FirebaseAuth.instance ตรงๆ ซึ่งพังทันทีเพราะเทสไม่มี Firebase.initializeApp()
// (ดู `[core/no-app] No Firebase App '[DEFAULT]' has been created`)
//
// แก้โดยฉีด FirebaseAuth/FirestoreService ปลอมเข้า AuthGate แทน (ดู
// lib/screens/auth/auth_gate.dart, lib/services/firestore_service.dart)
// แล้วเทส 2 branch ของการ routing ที่ทดสอบได้แบบสมบูรณ์:
//   1) ยังไม่ล็อกอิน            -> WelcomeScreen (หน้าแรกสุดของแอป)
//   2) ล็อกอินแล้วแต่ยังไม่มีข้อมูล user -> SetupScreen
//
// หมายเหตุ (สำคัญ — ยังไม่ครอบคลุม 100%):
// Branch ที่ 3 "ล็อกอินแล้ว + มีข้อมูล user แล้ว -> MainShell" ยังเทสแบบ
// pump เต็มไม่ได้ในตอนนี้ เพราะ MainShell ใช้ IndexedStack (ทุกแท็บถูกสร้าง
// พร้อมกันตั้งแต่แรก ไม่ได้สร้างแบบ lazy) และ DashboardScreen (รวมถึงแท็บอื่น)
// เรียก FirebaseAuth.instance / FirestoreService() ของจริงตรงๆ ใน initState()
// ของตัวเอง (คนละจุดกับ AuthGate) เลยยัง crash อยู่ดีแม้ AuthGate จะฉีด mock
// ให้แล้ว — ถ้าจะเทส branch นี้แบบเต็มรูปแบบ ต้องไปทำ dependency injection
// แบบเดียวกันนี้ต่อในแต่ละแท็บ (dashboard/appliance/analysis/settings) ซึ่ง
// เป็นงานแยกต่างหากที่ใหญ่กว่านี้ ไม่ใช่แค่แก้ widget_test.dart
import 'package:energy_home/screens/auth/auth_gate.dart';
import 'package:energy_home/screens/auth/setup_screen.dart';
import 'package:energy_home/screens/auth/welcome_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('AuthGate shows WelcomeScreen when no one is signed in',
      (tester) async {
    final auth = MockFirebaseAuth(signedIn: false);
    final firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());

    await tester.pumpWidget(
      wrap(AuthGate(auth: auth, firestoreService: firestoreService)),
    );
    await tester.pump(); // ให้ authStateChanges() ยิง event แรกออกมา

    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets(
      'AuthGate shows SetupScreen when signed in but no user document exists yet',
      (tester) async {
    final user = MockUser(uid: 'test-uid', email: 'dee@example.com');
    final auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    // ตั้งใจปล่อยว่าง ไม่มี users/test-uid เลย เพื่อจำลองบัญชีที่เพิ่งสมัคร
    final firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());

    await tester.pumpWidget(
      wrap(AuthGate(auth: auth, firestoreService: firestoreService)),
    );
    await tester.pump(); // authStateChanges() ยิง event
    await tester.pump(); // FirestoreService().getUser() future เสร็จ

    expect(find.byType(SetupScreen), findsOneWidget);
  });
}