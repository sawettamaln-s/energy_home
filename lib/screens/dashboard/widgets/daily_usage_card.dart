import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/daily_usage.dart';
import '../../../utils/thai_date_utils.dart';
import '../../../widgets/ui/app_card.dart';
import '../dashboard_loader.dart';
import '../dashboard_styles.dart';

// =====================================================================
// การ์ดการใช้รายวันของรอบนี้ — กราฟแท่งวันละแท่ง สลับไฟฟ้า/น้ำ พร้อมเส้นประ
// = ค่าเฉลี่ยต่อวันของบิลก่อน ให้เห็นว่าวันไหนใช้มาก และตอนนี้ใช้เร็ว/ช้ากว่า
// ปกติ โดยไม่ต้องอ่านตัวเลข (หน้าวิเคราะห์ดูระดับรายเดือน หน้านี้ดูรายวัน)
// วันที่จดเว้นช่วงเฉลี่ยหน่วยลงแต่ละวัน (ดู DailyUsage.spread) วันที่ยังไม่ถึง
// หรือยังไม่ได้จดเป็นแท่งเทาเตี้ย
// =====================================================================
class DailyUsageCard extends StatefulWidget {
  final DashboardData data;
  final int cycleDays;

  const DailyUsageCard({super.key, required this.data, required this.cycleDays});

  @override
  State<DailyUsageCard> createState() => _DailyUsageCardState();
}

class _DailyUsageCardState extends State<DailyUsageCard> {
  bool _showWater = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final accent = _showWater
        ? DashboardStyles.waterBorder
        : DashboardStyles.electricityBorder;
    final unit = _showWater ? 'ลบ.ม.' : 'หน่วย';
    final readings = _showWater
        ? [for (final l in data.waterLogs) (l.date, l.usedFromStart)]
        : [for (final l in data.electricityLogs) (l.date, l.usedFromStart)];
    final daily = DailyUsage.spread(
        cycleStart: data.cycleStart,
        cycleDays: widget.cycleDays,
        readings: readings);
    final reference = _showWater
        ? data.lastBillWaterPerDay
        : data.lastBillElectricityPerDay;
    final known = daily.whereType<double>().toList();
    final average = known.isEmpty
        ? 0.0
        : known.fold<double>(0, (a, b) => a + b) / known.length;
    final caption =
        TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('การใช้รายวัน',
                    style: TextStyle(
                        fontSize: AppTypography.s15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark)),
              ),
              _ToggleChip(
                label: 'ไฟฟ้า',
                selected: !_showWater,
                color: DashboardStyles.electricityBorder,
                onTap: () => setState(() => _showWater = false),
              ),
              const SizedBox(width: 6),
              _ToggleChip(
                label: 'น้ำ',
                selected: _showWater,
                color: DashboardStyles.waterBorder,
                onTap: () => setState(() => _showWater = true),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            known.isEmpty
                ? 'จดมิเตอร์แล้วกราฟจะแสดงการใช้แต่ละวันค่ะ'
                : 'เฉลี่ยวันละ ${NumberFormat('#,##0.#').format(average)} $unit',
            style: caption,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: _DailyBars(
              daily: daily,
              cycleStart: data.cycleStart,
              reference: reference,
              accent: accent,
              unit: unit,
            ),
          ),
          if (reference != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  child: CustomPaint(
                      size: const Size(16, 2),
                      painter: _DashPainter(Colors.grey.shade500)),
                ),
                const SizedBox(width: 6),
                Text('เฉลี่ยต่อวันของบิลก่อน', style: caption),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ปุ่มสลับไฟฟ้า/น้ำแบบเม็ดยาเล็ก
class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.14) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(label,
              style: TextStyle(
                  fontSize: AppTypography.s12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : Colors.grey.shade600)),
        ),
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  final List<double?> daily;
  final DateTime cycleStart;
  final double? reference;
  final Color accent;
  final String unit;

  const _DailyBars({
    required this.daily,
    required this.cycleStart,
    required this.reference,
    required this.accent,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final peak = [
      ...daily.whereType<double>(),
      reference ?? 0,
    ].fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = peak > 0 ? peak * 1.15 : 1.0;
    // วันที่ยังไม่มีข้อมูลเป็นแท่งเทาเตี้ยๆ ให้เห็นว่ารอบยังเหลืออีกกี่วัน
    final stub = maxY * 0.04;
    final last = daily.length - 1;
    final number = NumberFormat('#,##0.#');

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceBetween,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                // ป้ายวันที่ทุก 7 วัน + วันสุดท้ายของรอบ (เว้นถ้าชิดป้ายก่อนหน้า)
                final show = i % 7 == 0 || (i == last && last % 7 >= 3);
                if (!show) return const SizedBox.shrink();
                final d = cycleStart.add(Duration(days: i));
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${d.day}',
                      style: TextStyle(
                          fontSize: AppTypography.s10,
                          color: Colors.grey.shade500)),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(horizontalLines: [
          if (reference != null)
            HorizontalLine(
              y: reference!,
              color: Colors.grey.shade500,
              strokeWidth: 1,
              dashArray: const [4, 3],
            ),
        ]),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => AppColors.textDark,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final d = cycleStart.add(Duration(days: group.x));
              final value = daily[group.x];
              return BarTooltipItem(
                '${d.day} ${thaiMonthsShort[d.month - 1]}\n'
                '${value == null ? 'ยังไม่มีข้อมูล' : '${number.format(value)} $unit'}',
                const TextStyle(
                    color: Colors.white,
                    fontSize: AppTypography.s11,
                    fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < daily.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: daily[i] == null ? stub : daily[i]!.clamp(stub, maxY),
                color: daily[i] == null ? Colors.grey.shade200 : accent,
                width: 5,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ]),
        ],
      ),
      duration: const Duration(milliseconds: 300),
    );
  }
}

// เส้นประสั้นในคำอธิบายกราฟ
class _DashPainter extends CustomPainter {
  final Color color;

  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset((x + 4).clamp(0, size.width), size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
