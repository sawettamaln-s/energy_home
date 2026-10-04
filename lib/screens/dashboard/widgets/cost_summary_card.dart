import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../dashboard_loader.dart';
import '../dashboard_styles.dart';

// =====================================================================
// การ์ดค่าใช้จ่ายรอบนี้ — การ์ดเขียวบนสุด โชว์ยอดไฟฟ้า/น้ำที่ใช้ไปแล้ว 2 ช่อง
// ซ้าย-ขวา และแถบยอดคาดการณ์สิ้นรอบ (รวมไฟฟ้า+น้ำ ไม่รวมรายจ่ายประจำ)
// =====================================================================
class CostSummaryCard extends StatelessWidget {
  final DashboardData data;

  const CostSummaryCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    final hasForecast = data.hasForecastData;
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
              const Text('ประมาณการรอบบิลนี้',
                  style: TextStyle(
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
          // ยอดคาดการณ์สิ้นรอบ — pill จางๆ บนพื้นเขียว ถ้ายังไม่มีข้อมูลพอ
          // คำนวณอัตรา จะไม่โชว์เป็นตัวเลขคาดการณ์ (เพราะจะเท่ากับยอดปัจจุบัน
          // พอดี ดูเหมือนระบบฟันธงว่าใช้เท่านี้พอ) แต่บอกว่าต้องบันทึกมิเตอร์
          // หลังวันตัดรอบก่อน
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
                        ? 'ยอดคาดการณ์สิ้นรอบบิล: '
                            '${formatter.format(data.forecastTotal)} บาท'
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
