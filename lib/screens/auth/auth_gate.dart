import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../dashboard/dashboard_screen.dart';
import 'login_screen.dart';
import 'setup_screen.dart';

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
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
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

        // ยังไม่ได้ Login
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        // Login แล้ว → เช็คว่ามีข้อมูล Setup ไหม
        return FutureBuilder(
          future: FirestoreService().getUser(snapshot.data!.uid),
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
              return const SetupScreen();
            }

            // มีข้อมูลแล้ว → ไปหน้า Dashboard
            return const DashboardScreen();
          },
        );
      },
    );
  }
}