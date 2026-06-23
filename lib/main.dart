import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/setup_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermission();
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
          seedColor: const Color(0xFF2E7D32),
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
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
      ),
    );
  }
}
