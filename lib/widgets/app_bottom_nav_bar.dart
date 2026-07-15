import 'package:flutter/material.dart';

import '../screens/analysis/analysis_screen.dart';
import '../screens/appliance/appliance_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/settings/settings_screen.dart';

/// บาร์ล่างแบบ floating pill ใช้ร่วมกันทุกหน้า (หน้าหลัก/วิเคราะห์/อุปกรณ์/ตั้งค่า)
///
/// เดิมโค้ดนี้ก๊อปวางซ้ำอยู่ 4 ไฟล์ (dashboard, analysis, appliance, settings
/// ~280 บรรทัดรวมกัน) แยกออกมาเป็น widget กลางที่นี่ที่เดียว ทั้งหน้าตา UI
/// และ logic การสลับแท็บ
///
/// [onTap] — ถ้ามีมาจาก MainShell (ทางเข้าปกติของแอปหลัง login) จะแค่
/// setState สลับ index ใน IndexedStack ไม่มีการสร้างหน้าใหม่/โหลดข้อมูลซ้ำ
/// เลย ตัดปัญหาเดิมที่ทุกครั้งที่สลับแท็บ หน้าปลายทางจะถูกสร้างใหม่ทั้งหมด
/// ทำให้ initState ยิง fetch Firestore ซ้ำ + เห็น loading spinner วูบทุกครั้ง
///
/// ถ้าไม่มี [onTap] (เช่นหน้าที่ถูก push ตรงๆ แยกจาก MainShell) จะ fallback
/// กลับไปใช้ pushReplacement แบบเดิม กันไม่ให้พังในเคสที่ยังไม่ได้ผ่าน shell
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const AppBottomNavBar({super.key, required this.currentIndex, this.onTap});

  static const _items = [
    (icon: Icons.dashboard_rounded, label: 'หน้าหลัก'),
    (icon: Icons.bar_chart_rounded, label: 'วิเคราะห์'),
    (icon: Icons.electrical_services, label: 'อุปกรณ์'),
    (icon: Icons.settings_rounded, label: 'ตั้งค่า'),
  ];

  // map index -> หน้าปลายทาง (ลำดับต้องตรงกับ _items ด้านบนเสมอ)
  static final Map<int, WidgetBuilder> _destinations = {
    0: (_) => const DashboardScreen(),
    1: (_) => const AnalysisScreen(),
    2: (_) => const ApplianceScreen(),
    3: (_) => const SettingsScreen(),
  };

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return; // อยู่หน้านี้อยู่แล้ว ไม่ต้องทำอะไร

    // ทางหลัก: มาจาก MainShell -> แค่สลับ index ใน IndexedStack ไม่มีการ
    // สร้างหน้าใหม่/ยิง fetch ซ้ำ/เห็น loading กระพริบเหมือนเดิมอีกต่อไป
    if (onTap != null) {
      onTap!(index);
      return;
    }

    // Fallback: เผื่อหน้าไหนถูก push ตรงๆ แยกออกมาจาก MainShell (ไม่มี
    // onTap ส่งมาให้) ใช้ pushReplacement แบบเดิมกันไว้ไม่ให้พัง
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: _destinations[index]!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_items.length, (index) {
          final isSelected = index == currentIndex;
          final item = _items[index];
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onTap(context, index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 22,
                      color: isSelected
                          ? const Color(0xFF2E7D32)
                          : Colors.grey.shade500,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFF2E7D32)
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}