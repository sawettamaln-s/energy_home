import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../main_shell.dart';
import 'setup_screen.dart';
import 'welcome_screen.dart';

/// AuthGate = ตัวคอยฟัง auth state แล้วสลับ Login/Setup/Dashboard ให้อัตโนมัติ
///
/// เดิมโค้ดนี้อยู่ตรงๆใน main.dart (เป็น MaterialApp.home) ทำให้มันมีแค่
/// "ชุดเดียว" ตลอดทั้งแอป — ถ้าจุดไหนเผลอ Navigator.pushReplacement ทับ
/// route ที่ครอบ StreamBuilder ตัวนี้อยู่ (เช่นตอนสลับแท็บล่าง) ตัวฟัง
/// auth state ตัวนี้จะหลุดออกจาก widget tree ไปเลย ทำให้หลัง logout
/// แล้ว login ใหม่ ไม่มีอะไรคอยรับรู้ว่า login สำเร็จแล้วต้องไปหน้าไหนต่อ
///
/// แยกออกมาเป็น widget ของตัวเอง เพื่อให้จุดที่ logout สามารถ
/// `Navigator.pushAndRemoveUntil` กลับมาที่ AuthGate() ตัวใหม่ (สดๆ มีตัวฟัง
/// ติดมาด้วยเสมอ) แทนที่จะ push ไปแค่ LoginScreen() เปล่าๆแบบเดิม
class AuthGate extends StatelessWidget {
  // รับ auth/firestoreService แบบ optional เพื่อให้ทดสอบได้ (ฉีด
  // MockFirebaseAuth + FakeFirebaseFirestore เข้ามาแทน) — ตอนใช้งานจริงไม่ส่ง
  // param มา ก็ยัง fallback ไปใช้ FirebaseAuth.instance / FirestoreService()
  // (Firebase จริง) เหมือนเดิมทุกจุดที่เรียก const AuthGate() อยู่แล้ว
  const AuthGate({super.key, FirebaseAuth? auth, FirestoreService? firestoreService})
      : _auth = auth,
        _firestoreService = firestoreService;

  final FirebaseAuth? _auth;
  final FirestoreService? _firestoreService;

  FirebaseAuth get _authInstance => _auth ?? FirebaseAuth.instance;
  FirestoreService get _firestoreServiceInstance =>
      _firestoreService ?? FirestoreService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authInstance.authStateChanges(),
      builder: (context, snapshot) {
        // กำลังโหลดอยู่
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2E7D32),
              ),
            ),
          );
        }

        // ยังไม่ได้ Login → หน้าแรกสุด (Welcome) ให้เลือกเข้าสู่ระบบ/สมัคร
        if (!snapshot.hasData) {
          return const WelcomeScreen();
        }

        // Login แล้ว → เช็คว่ามีข้อมูล Setup ไหม
        return FutureBuilder(
          future: _firestoreServiceInstance.getUser(snapshot.data!.uid),
          builder: (context, userSnapshot) {
            // กำลังโหลดข้อมูล User
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF2E7D32),
                  ),
                ),
              );
            }

            // ไม่มีข้อมูล User → ไปหน้า Setup
            if (userSnapshot.data == null) {
              return SetupScreen(firestoreService: _firestoreServiceInstance);
            }

            // มีข้อมูลแล้ว → เข้าแอปหลัก (MainShell คุมทั้ง 4 แท็บ)
            return const MainShell();
          },
        );
      },
    );
  }
}