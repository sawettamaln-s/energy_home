import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/thai_date_utils.dart';
import '../dashboard_loader.dart';
import '../dashboard_styles.dart';

// =====================================================================
// แถวรายจ่ายประจำ — โชว์ยอดของเดือนบิลรอบนี้ กดแล้วพาไปหน้ารายจ่ายประจำ
// =====================================================================
class FixedCostRow extends StatelessWidget {
  final double amount;
  final VoidCallback onTap;

  const FixedCostRow({super.key, required this.amount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.v14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.v16, vertical: AppSpacing.v14),
        decoration: DashboardStyles.whiteCard(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.v8),
              decoration: BoxDecoration(
                color: AppColors.softGreenBg,
                borderRadius: BorderRadius.circular(AppSpacing.v10),
              ),
              child: const Icon(Icons.bookmark_outline,
                  color: DashboardStyles.primaryGreen, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'รายจ่ายประจำ',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppTypography.s14,
                    color: DashboardStyles.textDark),
              ),
            ),
            Text(
              '${formatter.format(amount)} บาท',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTypography.s15,
                color: DashboardStyles.textDark,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// การ์ดยอดรวม — พื้นขาว กรอบครีม
// ยอดที่ใช้ไปแล้วของรอบนี้ + รายจ่ายประจำ (ยังไม่ใช่ยอดบิลทั้งรอบ) ถ้ามี
// ข้อมูลพอคาดการณ์ ต่อท้ายด้วยยอดคาดการณ์ทั้งรอบรวมรายจ่ายประจำ
// =====================================================================
class BillSummaryCard extends StatelessWidget {
  final DashboardData data;

  const BillSummaryCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    final cycleEnd = data.cycleEnd;
    final fixedCost = data.billFixedCost;
    final usedSoFar = data.currentElectricityCost + data.currentWaterCost;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v18),
        border: Border.all(color: DashboardStyles.creamBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.v7),
                decoration: BoxDecoration(
                  color: AppColors.softOrangeBg,
                  borderRadius: BorderRadius.circular(AppSpacing.v9),
                ),
                child: const Icon(Icons.summarize_outlined,
                    color: Colors.orange, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ยอดรวมถึงตอนนี้ (บิล ${thaiMonths[cycleEnd.month - 1]} '
                  '${cycleEnd.year + 543})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTypography.s14_5,
                      color: DashboardStyles.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SummaryRow(
            label: 'ค่าไฟ + น้ำ (ใช้ไปแล้ว)',
            value: '${formatter.format(usedSoFar)} บาท',
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'รายจ่ายประจำ',
            value: '${formatter.format(fixedCost)} บาท',
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: DashboardStyles.creamBorder),
          const SizedBox(height: 16),
          // แถบ "รวมถึงตอนนี้" — แยกเป็นกล่องไฮไลต์ ให้เห็นยอดรวมชัด
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.v14, vertical: AppSpacing.v13),
            decoration: BoxDecoration(
              color: AppColors.softOrangeBg,
              borderRadius: BorderRadius.circular(AppSpacing.v12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'รวมถึงตอนนี้',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTypography.s15,
                    color: DashboardStyles.textDark,
                  ),
                ),
                Text(
                  '${formatter.format(usedSoFar + fixedCost)} บาท',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTypography.s19,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          if (data.hasForecastData) ...[
            const SizedBox(height: 12),
            _SummaryRow(
              label: 'คาดว่าบิลทั้งรอบ (รวมรายจ่ายประจำ)',
              value: '${formatter.format(data.forecastTotal + fixedCost)} บาท',
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
              color: DashboardStyles.textDark,
              fontSize: AppTypography.s13,
            )),
        Text(value,
            style: const TextStyle(
              color: DashboardStyles.textDark,
              fontSize: AppTypography.s14,
            )),
      ],
    );
  }
}

// =====================================================================
// แสดงแทนเนื้อหาหลักเมื่อโหลดข้อมูลไม่สำเร็จ — มีปุ่มลองใหม่ แทนตัวเลข 0
// เงียบๆ ที่ทำให้ผู้ใช้เข้าใจผิดว่าข้อมูลหาย
// =====================================================================
class DashboardLoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const DashboardLoadErrorView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 16),
              const Text(
                'โหลดข้อมูลไม่สำเร็จ',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTypography.s17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTypography.s14,
                    height: 1.5,
                    color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DashboardStyles.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.v32, vertical: AppSpacing.v12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.v12)),
                ),
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
