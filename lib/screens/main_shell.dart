import 'package:flutter/material.dart';

import 'analysis/analysis_screen.dart';
import 'appliance/appliance_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'settings/settings_screen.dart';

/// จุดเข้าเดียวของ "แอปหลังล็อกอิน" (4 แท็บ: หน้าหลัก/วิเคราะห์/อุปกรณ์/ตั้งค่า)
///
/// เดิมแต่ละแท็บเป็นคนละ Scaffold/route กัน สลับแท็บด้วย
/// Navigator.pushReplacement ผลคือทุกครั้งที่แตะแท็บ หน้าปลายทางถูกสร้าง
/// ใหม่ทั้งหมด -> initState ยิง fetch ข้อมูลจาก Firestore ใหม่ทุกครั้ง ->
/// เห็น loading spinner กระพริบทุกครั้งที่สลับแท็บ ทั้งที่ข้อมูลเพิ่งโหลด
/// ไปหมาดๆ เมื่อกี้เอง
///
/// ที่นี่แก้โดยเก็บทั้ง 4 หน้าไว้ใน IndexedStack เดียว (สร้างครั้งเดียว
/// ตอนเปิด MainShell) แล้วสลับแค่ "ใครโชว์อยู่" ตัว State ของแต่ละหน้า
/// (ข้อมูลที่โหลดมาแล้ว, scroll position, ค่าที่พิมพ์ค้างในฟอร์ม ฯลฯ) จะยัง
/// อยู่ครบเวลาสลับกลับมา ไม่ต้องโหลดซ้ำ
///
/// ผลพลอยได้: ปุ่ม back ตอนนี้พฤติกรรมถูกต้องขึ้นด้วย — เดิมเพราะสลับแท็บ
/// ด้วย pushReplacement ทำให้ stack ไม่เก็บหน้าก่อนหน้าไว้เลย กด back จาก
/// แท็บไหนก็มีสิทธิ์หลุดออกจากแอปทันที ตอนนี้ถ้าอยู่แท็บอื่นที่ไม่ใช่
/// หน้าหลัก กด back จะพากลับไปแท็บหน้าหลักก่อน ต้องกด back อีกทีถึงจะออก
/// จากแอปจริงๆ (พฤติกรรมมาตรฐานของแอปที่มี bottom nav ทั่วไป)
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

  // สร้างทั้ง 4 หน้าครั้งเดียวตอน initState แล้วเก็บไว้ใน list นี้ตลอด
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