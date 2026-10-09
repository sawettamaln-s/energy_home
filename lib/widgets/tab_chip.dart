import 'package:flutter/material.dart';

import '../styles/app_colors.dart';
import '../styles/app_spacing.dart';
import '../styles/app_typography.dart';

/// แท็บสลับไฟฟ้า/น้ำ พร้อมไอคอน check เมื่อกรอกข้อมูลครบ — ใช้ร่วมกันระหว่าง
/// หน้าบันทึกบิลย้อนหลังกับหน้าตั้งค่ามิเตอร์ต้นรอบให้หน้าตาตรงกันทั้งแอป
class TabChip extends StatelessWidget {
  const TabChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.v12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.v10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(AppSpacing.v12),
          border: Border.all(
            color: selected ? color : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? color : Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.s13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? color : Colors.grey.shade700,
              ),
            ),
            if (checked) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_circle, size: 14, color: Colors.green),
            ],
          ],
        ),
      ),
    );
  }
}

/// คู่แท็บ ไฟฟ้า | น้ำ ของฟอร์มกรอกใบแจ้งหนี้ (index 0 = ไฟฟ้า, 1 = น้ำ)
/// [electricityDone]/[waterDone] = ฝั่งนั้นกรอกครบแล้ว (ขึ้นเครื่องหมายถูก)
class UtilityTabChips extends StatelessWidget {
  const UtilityTabChips({
    super.key,
    required this.selectedIndex,
    required this.electricityDone,
    required this.waterDone,
    required this.onSelect,
  });

  final int selectedIndex;
  final bool electricityDone;
  final bool waterDone;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TabChip(
            label: 'ไฟฟ้า',
            icon: Icons.bolt,
            color: AppColors.electricityBorder,
            selected: selectedIndex == 0,
            checked: electricityDone,
            onTap: () => onSelect(0),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TabChip(
            label: 'น้ำ',
            icon: Icons.water_drop,
            color: AppColors.waterBorder,
            selected: selectedIndex == 1,
            checked: waterDone,
            onTap: () => onSelect(1),
          ),
        ),
      ],
    );
  }
}
