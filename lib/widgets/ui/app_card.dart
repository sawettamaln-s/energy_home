import 'package:flutter/material.dart';

import '../../styles/app_colors.dart';
import '../../styles/app_theme.dart';

// =====================================================================
// การ์ดพื้นขาวมาตรฐานของแอป — มุมมน 20 เงานุ่มสองชั้น (ชั้นใกล้คม + ชั้นไกล
// กระจาย) ให้ดูลอยจากพื้นครีมแบบเบาๆ ถ้าส่ง [onTap] ทั้งการ์ดกดได้พร้อม
// ripple ที่ตัดตามขอบมน
// =====================================================================
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final Color? borderColor;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = Colors.white,
    this.borderColor,
    this.radius = AppTheme.radiusLg,
  });

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: AppColors.primaryGreen.withValues(alpha: 0.05),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: AppColors.primaryGreen.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: borderColor == null
          ? BorderSide.none
          : BorderSide(color: borderColor!, width: 1.2),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: softShadow,
      ),
      child: Material(
        color: color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
