// เทส routing ของ AuthGate โดยฉีด FirebaseAuth/FirestoreService ปลอมแทนของจริง
// (ดู lib/screens/auth/auth_gate.dart, lib/services/firestore_service.dart)
// เพราะเทสไม่มี Firebase.initializeApp() — ครอบ 3 branch ที่ทดสอบได้สมบูรณ์:
//   1) ยังไม่ล็อกอิน                    -> WelcomeScreen (หน้าแรกสุดของแอป)
//   2) ล็อกอินแล้วแต่ยังไม่มีข้อมูล user  -> SetupScreen
//   3) ล็อกอินแล้วแต่โหลดข้อมูล user ไม่สำเร็จ (Firestore error) -> หน้า
//      "ลองใหม่" ไม่ใช่ SetupScreen (กันไม่ให้ SetupScreen.createUser() เขียน
//      ทับ document เดิมของ user ที่มีอยู่แล้วเงียบๆ) และปุ่ม "ลองใหม่" ต้อง
//      ยิง getUser() ใหม่จริง ไม่ใช่แค่ตกแต่งหน้าจอเฉยๆ
//
// หมายเหตุ (สำคัญ — ยังไม่ครอบคลุม 100%):
// Branch ที่ 4 "ล็อกอินแล้ว + มีข้อมูล user แล้ว -> MainShell" ยังเทสแบบ
// pump เต็มไม่ได้ในตอนนี้ เพราะ MainShell ใช้ IndexedStack (ทุกแท็บถูกสร้าง
// พร้อมกันตั้งแต่แรก ไม่ได้สร้างแบบ lazy) และ DashboardScreen (รวมถึงแท็บอื่น)
// เรียก FirebaseAuth.instance / FirestoreService() ของจริงตรงๆ ใน initState()
// ของตัวเอง (คนละจุดกับ AuthGate) เลยยัง crash อยู่ดีแม้ AuthGate จะฉีด mock
// ให้แล้ว — ถ้าจะเทส branch นี้แบบเต็มรูปแบบ ต้องไปทำ dependency injection
// แบบเดียวกันนี้ต่อในแต่ละแท็บ (dashboard/appliance/analysis/settings) ซึ่ง
// เป็นงานแยกต่างหากที่ใหญ่กว่านี้ ไม่ใช่แค่แก้ widget_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/screens/auth/auth_gate.dart';
import 'package:energy_home/screens/auth/setup_screen.dart';
import 'package:energy_home/screens/auth/welcome_screen.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

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

  testWidgets(
      'AuthGate shows a retry view (not SetupScreen) when loading the user '
      'fails, and the retry button re-attempts the load',
      (tester) async {
    final user = MockUser(uid: 'test-uid', email: 'dee@example.com');
    final auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    final firestore = FakeFirebaseFirestore();
    // จำลอง Firestore error (ออฟไลน์/permission-denied ฯลฯ) ตอนอ่าน
    // users/test-uid — MockDocumentReference เทียบเท่ากันด้วย path เดียวกัน
    // (ดู operator== ใน fake_cloud_firestore) เลย mock นี้ใช้ได้แม้
    // FirestoreService.getUser() จะสร้าง DocumentReference คนละ instance เอง
    whenCalling(Invocation.method(#get, null))
        .on(firestore.collection('users').doc('test-uid'))
        .thenThrow(
            FirebaseException(plugin: 'firestore', code: 'unavailable'));
    // นับจำนวนครั้งที่ getUser() ถูกเรียกจริง แทนที่จะดักจับเฟรม "กำลังโหลด"
    // ระหว่างกด "ลองใหม่" (mock ไม่มี I/O จริง ทั้ง error chain วิ่งจบในรอบ
    // microtask เดียวกับที่ pump() หนึ่งครั้งเคลียร์ให้หมด เลยจับเฟรมโหลดไม่ทัน)
    final firestoreService = _CountingFirestoreService(firestore);

    await tester.pumpWidget(
      wrap(AuthGate(auth: auth, firestoreService: firestoreService)),
    );
    await tester.pump(); // authStateChanges() ยิง event
    await tester.pump(); // getUser() future โยน error ออกมา

    expect(find.text('โหลดข้อมูลบัญชีไม่สำเร็จ'), findsOneWidget);
    // ต้องไม่ตกไป SetupScreen เด็ดขาด (จะเขียนทับ document เดิม)
    expect(find.byType(SetupScreen), findsNothing);
    expect(firestoreService.getUserCallCount, 1);

    // กดปุ่ม "ลองใหม่" ต้องยิง getUser() รอบใหม่จริง (ไม่ใช่ปุ่มตกแต่ง) — mock
    // เดิมยัง throw ซ้ำเหมือนเดิม (จำลองปัญหาเครือข่ายที่ยังไม่หาย) เลยยังเจอ
    // หน้า error เดิมอีกครั้ง แต่ call count ต้องเพิ่มขึ้นยืนยันว่ามีการลองจริง
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('โหลดข้อมูลบัญชีไม่สำเร็จ'), findsOneWidget);
    expect(firestoreService.getUserCallCount, 2);
  });
}

// ตัวห่อ FirestoreService นับจำนวนครั้งที่ getUser() ถูกเรียก ใช้เฉพาะในเทส
// เพื่อยืนยันว่าปุ่ม "ลองใหม่" ยิง request ใหม่จริง ไม่ใช่แค่โชว์ผลเดิมซ้ำ
class _CountingFirestoreService extends FirestoreService {
  _CountingFirestoreService(FirebaseFirestore firestore)
      : super(firestore: firestore);

  int getUserCallCount = 0;

  @override
  Future<UserModel?> getUser(String uid) {
    getUserCallCount++;
    return super.getUser(uid);
  }
}