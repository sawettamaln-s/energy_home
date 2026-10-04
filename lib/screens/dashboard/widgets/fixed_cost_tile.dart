import 'package:flutter/material.dart';

import '../../../widgets/ui/animated_amount.dart';
import '../../../widgets/ui/app_card.dart';
import '../../../widgets/ui/icon_badge.dart';
import '../dashboard_styles.dart';

// =====================================================================
// แถวรายจ่ายประจำของรอบนี้ — ยอดของเดือนบิลรอบนี้ (DashboardData.billFixedCost)
// แตะเพื่อไปหน้าจัดการรายจ่ายประจำ
// =====================================================================
class FixedCostTile extends StatelessWidget {
  final double amount;
  final VoidCallback onTap;

  const FixedCostTile({super.key, required this.amount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          const IconBadge(
              icon: Icons.bookmark_rounded,
              color: AppColors.primaryGreenLight,
              size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('รายจ่ายประจำ',
                    style: TextStyle(
                        fontSize: AppTypography.s14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark)),
                Text(amount > 0 ? 'แตะเพื่อจัดการ' : 'แตะเพื่อเพิ่มรายการ',
                    style: TextStyle(
                        fontSize: AppTypography.s11_5,
                        color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ยอดเงินชิดขวา กว้างไม่เกิน 150 ถ้าเลขยาว/ตัวอักษรใหญ่ย่อลงแทนการล้น
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: AnimatedAmount(
                value: amount,
                style: const TextStyle(
                    fontSize: AppTypography.s15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark),
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
        ],
      ),
    );
  }
}
