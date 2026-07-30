import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../dashboard/dashboard_styles.dart';
import '../main_shell.dart';
import 'setup_screen.dart';
import 'welcome_screen.dart';

/// AuthGate = ตัวคอยฟัง auth state แล้วสลับ Welcome/Setup/Dashboard ให้อัตโนมัติ
///
/// ต้องแยกเป็น widget ของตัวเอง (ไม่ใช่ MaterialApp.home ตรงๆ) เพื่อให้จุดที่
/// logout ทำ Navigator.pushAndRemoveUntil กลับมาที่ AuthGate() ตัวใหม่ได้เสมอ
/// (มีตัวฟัง authStateChanges ติดมาด้วยทุกครั้ง)
class AuthGate extends StatelessWidget {
  // รับ auth/firestoreService แบบ optional เพื่อฉีด MockFirebaseAuth +
  // FakeFirebaseFirestore ตอนเทสได้ — ไม่ส่งมาก็ fallback ไปใช้ของจริง
  const AuthGate(
      {super.key, FirebaseAuth? auth, FirestoreService? firestoreService})
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
                color: DashboardStyles.primaryGreen,
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
                    color: DashboardStyles.primaryGreen,
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
