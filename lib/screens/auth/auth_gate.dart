import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
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
          return const _LoadingScaffold();
        }

        // ยังไม่ได้ Login → หน้าแรกสุด (Welcome) ให้เลือกเข้าสู่ระบบ/สมัคร
        if (!snapshot.hasData) {
          return const WelcomeScreen();
        }

        // Login แล้ว → เช็คว่ามีข้อมูล Setup ไหม
        // ผูก key กับ uid เพื่อให้สลับบัญชีแล้วโหลดข้อมูลของบัญชีใหม่เสมอ
        return _UserGate(
          key: ValueKey(snapshot.data!.uid),
          uid: snapshot.data!.uid,
          auth: _authInstance,
          firestoreService: _firestoreServiceInstance,
        );
      },
    );
  }
}

/// โหลดข้อมูล user จาก Firestore แล้วเลือกหน้า Setup / MainShell
///
/// แยกเป็น StatefulWidget เพื่อ (1) เก็บ Future ไว้ไม่ให้ยิง Firestore ซ้ำทุกครั้ง
/// ที่ rebuild และ (2) กด "ลองใหม่" ได้เมื่อโหลดไม่สำเร็จ
///
/// สำคัญ: ถ้าโหลดไม่สำเร็จ (ออฟไลน์/permission error) ต้อง "ไม่" ตกไปหน้า Setup
/// เพราะ SetupScreen จะ createUser() แบบ set() ทับ document เดิมทั้งก้อน
/// Setup จะแสดงเฉพาะกรณีที่โหลดสำเร็จและยืนยันแล้วว่าไม่มี document จริงๆ
class _UserGate extends StatefulWidget {
  const _UserGate({
    super.key,
    required this.uid,
    required this.auth,
    required this.firestoreService,
  });

  final String uid;
  final FirebaseAuth auth;
  final FirestoreService firestoreService;

  @override
  State<_UserGate> createState() => _UserGateState();
}

class _UserGateState extends State<_UserGate> {
  late Future<UserModel?> _userFuture;

  @override
  void initState() {
    super.initState();
    _userFuture = widget.firestoreService.getUser(widget.uid);
  }

  void _retry() {
    setState(() {
      _userFuture = widget.firestoreService.getUser(widget.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: _userFuture,
      builder: (context, userSnapshot) {
        // กำลังโหลดข้อมูล User
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }

        // โหลดไม่สำเร็จ → ห้ามไป Setup (กันเขียนทับข้อมูลเดิม) ให้ลองใหม่แทน
        if (userSnapshot.hasError) {
          return _LoadErrorScaffold(
            onRetry: _retry,
            onSignOut: () => widget.auth.signOut(),
          );
        }

        // โหลดสำเร็จแต่ไม่มีข้อมูล User → บัญชีใหม่ ไปหน้า Setup
        if (userSnapshot.data == null) {
          return SetupScreen(firestoreService: widget.firestoreService);
        }

        // มีข้อมูลแล้ว → เข้าแอปหลัก (MainShell คุมทั้ง 4 แท็บ)
        return const MainShell();
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: DashboardStyles.primaryGreen,
        ),
      ),
    );
  }
}

class _LoadErrorScaffold extends StatelessWidget {
  const _LoadErrorScaffold({
    required this.onRetry,
    required this.onSignOut,
  });

  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 56, color: Colors.grey.shade500),
                const SizedBox(height: 16),
                const Text(
                  'โหลดข้อมูลบัญชีไม่สำเร็จ',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, height: 1.5, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DashboardStyles.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('ลองใหม่'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('ออกจากระบบ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}