import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/dashboard/dashboard_styles.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.instance.init();
  // ขอสิทธิ์แจ้งเตือนทำใน MainShell หลังเข้าแอปแล้ว (ไม่บล็อกหน้าแรก)
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Energy Home',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: DashboardStyles.primaryGreen,
        ),
        useMaterial3: true,
      ),
      // จำกัดสเกลฟอนต์ของระบบ (การตั้งค่า "ขนาดตัวอักษร" ในมือถือ) ไว้ไม่ให้
      // เล็ก/ใหญ่เกินไป กันเลย์เอาต์ที่ยังไม่ได้ใช้ context.rf()/AppTypography.
      // scaled() (ส่วนใหญ่ของแอปตอนนี้) ล้น/บี้กันบนจอเล็กหรือเครื่องที่ผู้ใช้
      // ตั้งฟอนต์ใหญ่มาก — ครอบทั้งแอปที่จุดเดียว ไม่ต้องแก้ทีละหน้า
      builder: (context, child) {
        final clamped = MediaQuery.textScalerOf(context)
            .clamp(minScaleFactor: 0.85, maxScaleFactor: 1.3);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: clamped),
          child: child!,
        );
      },
      home: const AuthGate(),
    );
  }
}