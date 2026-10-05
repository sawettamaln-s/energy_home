import 'package:flutter/material.dart';

import '../../../utils/thai_date_utils.dart';
import '../../../widgets/ui/animated_amount.dart';
import '../../../widgets/ui/cycle_ring.dart';
import '../dashboard_loader.dart';
import '../dashboard_styles.dart';

// =====================================================================
// การ์ดสรุปบิลรอบนี้ — การ์ดเด่นบนสุด แสดงเฉพาะตัวเลขหลัก (รายละเอียดแยก
// ไฟ/น้ำอยู่ที่ MeterSummaryCard และรายจ่ายประจำที่ FixedCostTile ด้านล่าง):
//   1) ช่วงวันของรอบ + เดือนที่ออกบิล
//   2) วงแหวนวันที่เหลือในรอบ + ตัวเลขหลักเป็นยอดที่ใช้ไปแล้ว (รวมรายจ่าย
//      ประจำ) — แอปเน้นติดตามการใช้จริง หน่วยที่ใช้แยกอยู่ในการ์ดไฟฟ้า/น้ำ
//   3) บรรทัดรอง: ยอดคาดการณ์สิ้นรอบบิลแบบปัดเลขกลม พร้อมชิป "ประมาณการ
//      เบื้องต้น" ช่วงต้นรอบ และชิปเทียบกับบิลก่อน (ข้อมูลยังไม่พอคาดการณ์
//      แสดงคำแนะนำให้บันทึกมิเตอร์แทน)
// =====================================================================
class BillHeroCard extends StatelessWidget {
  final DashboardData data;
  final int remainingDays;
  final int daysElapsed;
  final int cycleLengthDays;

  const BillHeroCard({
    super.key,
    required this.data,
    required this.remainingDays,
    required this.daysElapsed,
    required this.cycleLengthDays,
  });

  String _shortDate(DateTime d) => '${d.day} ${thaiMonthsShort[d.month - 1]}';

  // ผ่านไปไม่ถึงกี่วันนับเป็นช่วงต้นรอบ (ยอดคาดการณ์ยังไม่นิ่ง)
  static const int earlyCycleDays = 7;

  // ปัดยอดคาดการณ์เป็นตัวเลขกลม: ต่ำกว่าพันปัดหลักสิบ ตั้งแต่พันปัดหลักร้อย
  static double roundEstimate(double v) {
    final step = v < 1000 ? 10 : 100;
    return (v / step).round() * step.toDouble();
  }

  // ชิปเทียบยอดคาดการณ์กับบิลก่อน (ค่าไฟ+ค่าน้ำ) — ต่างไม่ถึง 5% ถือว่า
  // ใกล้เคียง สูงกว่าใช้ส้มอ่อน (ไม่ใช้แดงให้ตกใจ) ต่ำกว่า/ใกล้เคียงใช้เขียวอ่อน
  static Widget? _comparisonChip(double? changePercent) {
    if (changePercent == null) return null;
    final pct = changePercent.abs().round();
    if (changePercent.abs() < 5) {
      return const _HeroChip(
          icon: Icons.trending_flat_rounded,
          text: 'ใกล้เคียงบิลก่อน',
          color: AppColors.onHeroDown);
    }
    if (changePercent > 0) {
      return _HeroChip(
          icon: Icons.trending_up_rounded,
          text: 'สูงกว่าบิลก่อนประมาณ $pct%',
          color: AppColors.onHeroUp);
    }
    return _HeroChip(
        icon: Icons.trending_down_rounded,
        text: 'ต่ำกว่าบิลก่อนประมาณ $pct%',
        color: AppColors.onHeroDown);
  }

  @override
  Widget build(BuildContext context) {
    final user = data.user;
    final hasForecast = data.hasForecastData;
    final cycleEnd = data.cycleEnd;
    final fixedCost = data.billFixedCost;
    final usedSoFar =
        data.currentElectricityCost + data.currentWaterCost + fixedCost;
    // ผู้ใช้ใหม่ที่ยังไม่ได้ตั้งวันตัดรอบบิล ยังไม่มีรอบจริงให้นับวัน
    final cycleReady = user?.billingDayConfigured ?? true;
    final progress =
        cycleLengthDays > 0 ? daysElapsed / cycleLengthDays : 0.0;
    // วันสุดท้ายของรอบ = วันก่อนวันตัดรอบครั้งถัดไป
    final lastDay = cycleEnd.subtract(const Duration(days: 1));
    const white70 = TextStyle(color: Colors.white70, fontSize: AppTypography.s12);
    // ช่วงต้นรอบข้อมูลยังน้อย ยอดคาดการณ์ยังแกว่งได้มาก — บอกผู้ใช้ไว้ก่อน
    final isEarly = cycleReady && daysElapsed < earlyCycleDays;
    final chips = <Widget>[
      if (isEarly)
        const _HeroChip(
            icon: Icons.hourglass_top_rounded,
            text: 'ประมาณการเบื้องต้น',
            color: Colors.white),
      if (_comparisonChip(data.forecastChangeVsLastBill) case final chip?) chip,
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl - 4),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryGreenLight, AppColors.primaryGreen],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl - 4),
        child: Stack(
          children: [
            // วงกลมโปร่งตกแต่งมุมขวาบน ให้การ์ดมีมิติ
            Positioned(
              right: -40,
              top: -50,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ช่วงวันที่ใช้ไฟ/น้ำของรอบนี้ (ชิปซ้าย) + เดือนที่ออกใบแจ้งหนี้
                  // (ขวา) — บิลตั้งชื่อตามเดือนที่ปิดรอบ จึงบอกทั้งสองอย่างให้
                  // เห็นว่าใช้ช่วงไหน แล้วจะได้บิลเดือนอะไร จอแคบ/ตัวอักษรใหญ่
                  // ย่อด้วย ... แทนการล้นขอบ
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            cycleReady
                                ? 'รอบ ${_shortDate(data.cycleStart)} – ${_shortDate(lastDay)}'
                                : 'รอบบิลนี้',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppTypography.s12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      if (cycleReady) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'บิลเดือน ${thaiMonthsShort[cycleEnd.month - 1]} '
                            '${cycleEnd.year + 543}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: white70,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      CycleRing(
                        size: 100,
                        progress: cycleReady ? progress : 0,
                        centerValue: cycleReady ? '$remainingDays' : '–',
                        centerLabel: cycleReady ? 'วันที่เหลือ' : 'ยังไม่ตั้งรอบ',
                      ),
                      const SizedBox(width: 20),
                      // ตัวเลขหลักเป็นยอดจริงที่ใช้ไปแล้ว (ข้อเท็จจริงจากเลขมิเตอร์)
                      // ยอดคาดการณ์เป็นบรรทัดรองด้านล่าง
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ใช้ไปแล้วรอบนี้',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: AppTypography.s12_5,
                                  height: 1.3),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: AnimatedAmount(
                                value: usedSoFar,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: AppTypography.s24,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2),
                              ),
                            ),
                            if (fixedCost > 0) ...[
                              const SizedBox(height: 4),
                              const Text('รวมรายจ่ายประจำแล้ว', style: white70),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                  const SizedBox(height: 14),
                  if (!hasForecast)
                    const Text(
                      'บันทึกมิเตอร์หลังวันตัดรอบอย่างน้อย 1 วัน '
                      'เพื่อดูว่าสิ้นรอบบิลน่าจะประมาณเท่าไรค่ะ',
                      style: white70,
                    )
                  else ...[
                    // ยอดคาดการณ์ปัดเป็นตัวเลขกลมๆ ไม่มีทศนิยม ให้อ่านออกว่า
                    // เป็นการประมาณ ไม่ใช่ยอดในใบแจ้งหนี้
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ถ้าใช้แบบนี้ต่อไป สิ้นรอบบิลน่าจะประมาณ',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: AppTypography.s12_5,
                                    height: 1.3),
                              ),
                              // ยอดนี้ = ค่าไฟ + ค่าน้ำ (ตรงกับการ์ดคาดการณ์หน้า
                              // วิเคราะห์) + รายจ่ายประจำ บอกไว้ให้บวกตามได้
                              if (fixedCost > 0) ...[
                                const SizedBox(height: 2),
                                const Text('(รวมรายจ่ายประจำแล้ว)',
                                    style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: AppTypography.s11)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // ตัวเลขชิดขวา ถ้ายาวเกินพื้นที่ย่อลงแทนการล้น
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: AnimatedAmount(
                              value: roundEstimate(data.forecastTotal + fixedCost),
                              pattern: '#,##0',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: AppTypography.s16,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 4, children: chips),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ชิปเล็กบนการ์ดเขียว: ไอคอน + ข้อความสีเดียวกัน บนพื้นขาวโปร่ง
class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _HeroChip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: AppTypography.s11,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
