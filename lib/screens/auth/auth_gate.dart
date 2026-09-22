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

// ไม่ใช้ FutureBuilder — ใส่ตัวจับ error (onError) ในบรรทัดเดียวกับตอนสร้าง
// Future เลย (.then(..., onError: ...)) การแนบ error handler ทันทีแบบนี้
// การันตีว่า error ถูก "handled" ตั้งแต่ frame เดียวกัน ไม่มีช่องให้หลุดเป็น
// unhandled exception เหมือนที่เคยเจอตอนพึ่ง FutureBuilder เฉยๆ
enum _LoadStatus { loading, error, loaded }

class _UserGateState extends State<_UserGate> {
  _LoadStatus _status = _LoadStatus.loading;
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _status = _LoadStatus.loading);
    widget.firestoreService.getUser(widget.uid).then(
      (user) {
        if (!mounted) return;
        setState(() {
          _user = user;
          _status = _LoadStatus.loaded;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _status = _LoadStatus.error);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _LoadStatus.loading:
        return const _LoadingScaffold();
      // โหลดไม่สำเร็จ → ห้ามไป Setup (กันเขียนทับข้อมูลเดิม) ให้ลองใหม่แทน
      case _LoadStatus.error:
        return _LoadErrorScaffold(
          onRetry: _load,
          onSignOut: () => widget.auth.signOut(),
        );
      case _LoadStatus.loaded:
        // โหลดสำเร็จแต่ไม่มีข้อมูล User → บัญชีใหม่ ไปหน้า Setup
        if (_user == null) {
          return SetupScreen(firestoreService: widget.firestoreService);
        }
        // มีข้อมูลแล้ว → เข้าแอปหลัก (MainShell คุมทั้ง 4 แท็บ)
        return const MainShell();
    }
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 56, color: Colors.grey.shade500),
                const SizedBox(height: 16),
                const Text(
                  'โหลดข้อมูลบัญชีไม่สำเร็จ',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppTypography.s17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: AppTypography.s14, height: 1.5, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DashboardStyles.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.v14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.v12)),
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