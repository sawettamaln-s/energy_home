import 'package:flutter/material.dart';

import '../../styles/app_colors.dart';
import '../../styles/app_spacing.dart';
import '../../styles/app_theme.dart';
import '../../styles/app_typography.dart';

// ตัวเลือกหนึ่งช่องของ SegmentedSwitch
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  final Color? iconColor; // สีไอคอนตอนถูกเลือก (ไม่ส่ง = สีตัวอักษร)

  const SegmentOption({required this.value, required this.label, this.icon, this.iconColor});
}

// แถบสลับแบบชิ้นเดียวต่อกัน — พื้นครีม ช่องที่เลือกเป็นพื้นขาวยกขึ้น
// ใช้กับตัวเลือก 2–3 ทางที่เลือกได้ทีละอย่าง (เช่น ไฟฟ้า/น้ำ, ยอดเงิน/เลขมิเตอร์)
// compact = แถบเล็กสำหรับตัวเลือกรองที่วางชิดขอบ กว้างตามเนื้อหา
class SegmentedSwitch<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool compact;

  const SegmentedSwitch({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact ? 30.0 : 38.0;
    final fontSize = compact ? AppTypography.s12 : AppTypography.s13;

    Widget segment(SegmentOption<T> o) {
      final isSelected = o.value == selected;
      final child = Semantics(
        button: true,
        selected: isSelected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!isSelected) onChanged(o.value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: height,
            padding: EdgeInsets.symmetric(horizontal: compact ? AppSpacing.v10 : AppSpacing.v8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              boxShadow: isSelected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 1))]
                  : null,
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (o.icon != null) ...[
                  Icon(o.icon,
                      size: compact ? 14 : 16,
                      color: isSelected ? (o.iconColor ?? AppColors.textDark) : Colors.grey.shade500),
                  const SizedBox(width: AppSpacing.v4),
                ],
                Flexible(
                  child: Text(o.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppColors.textDark : Colors.grey.shade600)),
                ),
              ],
            ),
          ),
        ),
      );
      // compact กว้างตามเนื้อหา แต่ถ้าที่ไม่พอ (จอแคบ/ตัวอักษรใหญ่) ยอมย่อป้ายแทนการล้น
      return compact ? Flexible(child: child) : Expanded(child: child);
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.v3),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm + AppSpacing.v3),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [for (final o in options) segment(o)],
      ),
    );
  }
}
