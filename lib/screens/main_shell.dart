import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import 'analysis/analysis_screen.dart';
import 'appliance/appliance_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'settings/settings_screen.dart';

/// จุดเข้าเดียวของ "แอปหลังล็อกอิน" (4 แท็บ: หน้าหลัก/วิเคราะห์/อุปกรณ์/ตั้งค่า)
///
/// เก็บทั้ง 4 หน้าไว้ใน IndexedStack เดียว (สร้างครั้งเดียวตอนเปิด MainShell)
/// แล้วสลับแค่ "ใครโชว์อยู่" ตัว State ของแต่ละหน้า (ข้อมูลที่โหลดมาแล้ว,
/// scroll position, ค่าที่พิมพ์ค้างในฟอร์ม ฯลฯ) จะยังอยู่ครบเวลาสลับกลับมา
/// ไม่ต้องโหลดซ้ำ และไม่เห็น loading spinner กระพริบทุกครั้งที่สลับแท็บ
///
/// ปุ่ม back: ถ้าอยู่แท็บอื่นที่ไม่ใช่หน้าหลัก กด back จะพากลับไปแท็บหน้าหลัก
/// ก่อน ต้องกด back อีกทีถึงจะออกจากแอปจริงๆ (พฤติกรรมมาตรฐานของแอปที่มี
/// bottom nav)
class MainShell extends StatefulWidget {
  final int initialIndex;

  // ส่งต่อให้ DashboardScreen เฉพาะตอนเพิ่ง setup เสร็จหมาดๆ (ดูคอมเมนต์ใน
  // DashboardScreen.justCompletedSetup)
  final bool justCompletedSetup;

  const MainShell({
    super.key,
    this.initialIndex = 0,
    this.justCompletedSetup = false,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex = widget.initialIndex;

  // สร้างทั้ง 4 หน้าครั้งเดียว (ตอน build ครั้งแรก) แล้วเก็บไว้ใน list นี้ตลอด
  // อายุของ MainShell — ห้ามสร้างใหม่ใน build() เด็ดขาด ไม่งั้น IndexedStack
  // จะเสียประโยชน์ (State ของแต่ละหน้าจะโดนสร้างใหม่ทุกครั้งที่ build ใหม่)
  late final List<Widget> _tabs = [
    DashboardScreen(
      justCompletedSetup: widget.justCompletedSetup,
      onNavTap: _onNavTap,
    ),
    AnalysisScreen(onNavTap: _onNavTap),
    ApplianceScreen(onNavTap: _onNavTap),
    SettingsScreen(onNavTap: _onNavTap),
  ];

  @override
  void initState() {
    super.initState();
    // ขอสิทธิ์แจ้งเตือนหลังเข้าแอปแล้ว (ไม่ใช่ใน main() ก่อน runApp) เพื่อไม่ให้
    // หน้าจอค้างรอผู้ใช้ตอบ dialog ตั้งแต่เปิดแอปครั้งแรก — ไม่ await เพราะไม่มี
    // อะไรต้องรอผลก่อนใช้งานต่อ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.requestPermission().catchError((_) => false);
    });
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // กด back ได้ตรงๆ (ออกจากแอป/กลับ route ก่อนหน้า) เฉพาะตอนอยู่แท็บ
      // หน้าหลักเท่านั้น แท็บอื่นให้ดักไว้ก่อน
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() => _currentIndex = 0);
      },
      child: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
    );
  }
}