import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/thai_date_utils.dart';
import '../dashboard_loader.dart';
import '../dashboard_styles.dart';

// =====================================================================
// การ์ดสรุปบิลรอบนี้ — การ์ดเขียวบนสุดใบเดียวที่รวมตัวเลขค่าใช้จ่ายทั้งหมด:
//   1) ค่าไฟ/ค่าน้ำที่ใช้ไปแล้ว 2 ช่องซ้าย-ขวา
//   2) รายจ่ายประจำของเดือนบิล (แตะเพื่อไปจัดการ) + รวมถึงตอนนี้
//   3) แถบคาดการณ์บิลทั้งรอบ (รวมรายจ่ายประจำ)
// =====================================================================
class CostSummaryCard extends StatelessWidget {
  final DashboardData data;
  final VoidCallback onFixedCostTap;

  const CostSummaryCard({
    super.key,
    required this.data,
    required this.onFixedCostTap,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    final hasForecast = data.hasForecastData;
    final cycleEnd = data.cycleEnd;
    final fixedCost = data.billFixedCost;
    final usedSoFar = data.currentElectricityCost + data.currentWaterCost;
    const muted = TextStyle(color: Colors.white70, fontSize: AppTypography.s13);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v20),
      decoration: BoxDecoration(
        color: DashboardStyles.primaryGreen,
        borderRadius: BorderRadius.circular(AppSpacing.v20),
        boxShadow: [
          BoxShadow(
            color: DashboardStyles.primaryGreen.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined,
                  color: Colors.white.withValues(alpha: 0.85), size: 16),
              const SizedBox(width: 6),
              Text(
                  'ประมาณการบิล ${thaiMonths[cycleEnd.month - 1]} '
                  '${cycleEnd.year + 543}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: AppTypography.s13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CostItem(
                  icon: Icons.bolt,
                  label: 'ค่าไฟฟ้า',
                  amount: '${formatter.format(data.currentElectricityCost)} บาท',
                  sub: '${data.currentElectricityUnits.toStringAsFixed(1)} หน่วย',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _CostItem(
                  icon: Icons.water_drop,
                  label: 'ค่าน้ำ',
                  amount: '${formatter.format(data.currentWaterCost)} บาท',
                  sub: '${data.currentWaterUnits.toStringAsFixed(1)} ลบ.ม.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.2)),
          // รายจ่ายประจำ — แตะทั้งแถวเพื่อไปหน้ารายจ่ายประจำ
          InkWell(
            onTap: onFixedCostTap,
            borderRadius: BorderRadius.circular(AppSpacing.v8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.v10),
              child: Row(
                children: [
                  const Expanded(child: Text('รายจ่ายประจำ', style: muted)),
                  Text('${formatter.format(fixedCost)} บาท', style: muted),
                  const Icon(Icons.chevron_right,
                      color: Colors.white70, size: 18),
                ],
              ),
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text('รวมถึงตอนนี้',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: AppTypography.s14,
                        fontWeight: FontWeight.w600)),
              ),
              Text('${formatter.format(usedSoFar + fixedCost)} บาท',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTypography.s17,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          // คาดการณ์บิลทั้งรอบ — pill จางๆ บนพื้นเขียว ถ้ายังไม่มีข้อมูลพอคำนวณ
          // อัตรา จะไม่โชว์เป็นตัวเลขคาดการณ์ (เพราะจะเท่ากับยอดปัจจุบันพอดี
          // ดูเหมือนระบบฟันธงว่าใช้เท่านี้พอ) แต่บอกว่าต้องบันทึกมิเตอร์หลังวัน
          // ตัดรอบก่อน
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.v8, horizontal: AppSpacing.v12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.v10),
            ),
            child: Row(
              children: [
                Icon(
                  hasForecast ? Icons.trending_up : Icons.info_outline,
                  color: Colors.white.withValues(alpha: hasForecast ? 1 : 0.75),
                  size: 15,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasForecast
                        ? 'คาดว่าบิลทั้งรอบ (รวมรายจ่ายประจำ): '
                            '${formatter.format(data.forecastTotal + fixedCost)} บาท'
                        : 'บันทึกมิเตอร์หลังวันตัดรอบอย่างน้อย 1 วัน เพื่อเริ่มคาดการณ์',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: hasForecast ? 1 : 0.75),
                      fontSize: AppTypography.s12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ช่องย่อยไฟฟ้า/น้ำในการ์ดเขียว: ไอคอน + ชื่อรายการ + ยอดเงิน + หน่วยที่ใช้
class _CostItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String amount;
  final String sub;

  const _CostItem({
    required this.icon,
    required this.label,
    required this.amount,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: AppTypography.s12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(amount,
            style: const TextStyle(
                color: Colors.white,
                fontSize: AppTypography.s20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(sub,
            style: const TextStyle(
                color: Colors.white60, fontSize: AppTypography.s11)),
      ],
    );
  }
}
