import 'package:flutter/material.dart';

import '../screens/analysis/analysis_screen.dart';
import '../screens/appliance/appliance_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/dashboard/dashboard_styles.dart';
import '../screens/settings/settings_screen.dart';

/// บาร์ล่างแบบแคปซูลลอย ใช้ตัวเดียวใน MainShell (หน้าหลัก/วิเคราะห์/อุปกรณ์/ตั้งค่า)
///
/// หน้าที่เลือกอยู่มีแคปซูลเขียวจางรองไอคอนกับป้ายชื่อ (ไอคอน/ชื่อสีเขียว) เวลาเปลี่ยนแท็บแคปซูล
/// จะเลื่อนไปหาแท็บใหม่แบบเด้งเล็กน้อย และไอคอนของแท็บใหม่ขยายเด้งขึ้นมา
/// ป้ายชื่อแสดงทุกปุ่มเสมอ ผู้ใช้ไม่ต้องเดาความหมายไอคอน ถ้าเครื่องปิด
/// แอนิเมชันไว้ (MediaQuery.disableAnimations) จะสลับทันทีไม่มีการเคลื่อนไหว
///
/// [onTap] — มาจาก MainShell (ทางเข้าปกติของแอปหลัง login) แค่สลับ index ใน
/// IndexedStack ไม่มีการสร้างหน้าใหม่/โหลดข้อมูลซ้ำ ถ้าไม่มี [onTap] (หน้าที่ถูก
/// push ตรงๆ แยกจาก MainShell) จะใช้ pushReplacement แทน
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const AppBottomNavBar({super.key, required this.currentIndex, this.onTap});

  // ไอคอนเส้น = ยังไม่เลือก, ไอคอนทึบ = หน้าที่อยู่ตอนนี้
  static const _items = [
    (icon: Icons.home_outlined, active: Icons.home_rounded, label: 'หน้าหลัก'),
    (icon: Icons.bar_chart_outlined, active: Icons.bar_chart_rounded, label: 'วิเคราะห์'),
    (icon: Icons.electrical_services_outlined, active: Icons.electrical_services, label: 'อุปกรณ์'),
    (icon: Icons.settings_outlined, active: Icons.settings_rounded, label: 'ตั้งค่า'),
  ];

  // map index -> หน้าปลายทาง (ลำดับต้องตรงกับ _items ด้านบนเสมอ)
  static final Map<int, WidgetBuilder> _destinations = {
    0: (_) => const DashboardScreen(),
    1: (_) => const AnalysisScreen(),
    2: (_) => const ApplianceScreen(),
    3: (_) => const SettingsScreen(),
  };

  static const _height = 64.0;
  static const _inset = 6.0; // ระยะจากขอบบาร์ถึงแคปซูลที่เลือก

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    if (onTap != null) {
      onTap!(index);
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: _destinations[index]!));
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final slide = reduceMotion ? Duration.zero : const Duration(milliseconds: 420);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v4, AppSpacing.v16, AppSpacing.v12),
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_height / 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / _items.length;
            return Stack(
              children: [
                // แคปซูลของแท็บที่เลือก — easeOutBack ทำให้เลยเป้านิดหนึ่งแล้วเด้งกลับ
                AnimatedPositioned(
                  duration: slide,
                  curve: Curves.easeOutBack,
                  left: itemWidth * currentIndex + _inset,
                  top: _inset,
                  bottom: _inset,
                  width: itemWidth - _inset * 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(_height / 2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (index, item) in _items.indexed)
                      Expanded(
                        child: _NavItem(
                          icon: index == currentIndex ? item.active : item.icon,
                          label: item.label,
                          selected: index == currentIndex,
                          reduceMotion: reduceMotion,
                          onTap: () => _onTap(context, index),
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryGreen : Colors.grey.shade600;
    final fade = reduceMotion ? Duration.zero : const Duration(milliseconds: 200);

    // ไอคอนของแท็บที่เพิ่งถูกเลือกขยายจาก 0.7 เด้งกลับเป็นขนาดปกติ
    // (key เปลี่ยนตาม selected เพื่อให้แอนิเมชันเริ่มใหม่ทุกครั้งที่ถูกเลือก)
    final iconWidget = TweenAnimationBuilder<double>(
      key: ValueKey(selected),
      tween: Tween(begin: selected && !reduceMotion ? 0.7 : 1, end: 1),
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: AnimatedSwitcher(
        duration: fade,
        child: Icon(icon, key: ValueKey(icon), size: 22, color: color),
      ),
    );

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        highlightShape: BoxShape.circle,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: AppSpacing.v2),
              AnimatedDefaultTextStyle(
                duration: fade,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: AppTypography.s11_5,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
