part of 'analysis_screen.dart';

// =====================================================================
// ตัววาดกราฟแท่ง — slots แต่ละช่องคือ 1 แท่ง (null = เดือนนั้นไม่มีบิล
// เว้นที่ว่างไว้ ไม่ให้แท่งเดือนอื่นเลื่อนมาแทนที่) labels คือป้ายใต้แท่ง
// ใช้ร่วมกันทั้งการ์ด (6 เดือนล่าสุด) และหน้าประวัติ (ม.ค.-ธ.ค. ของปีที่เลือก)
// forecastValues (ถ้ามี) ต่อท้ายเป็นแท่งประ พร้อมเส้น "วันนี้" คั่น — ใช้เฉพาะ
// ในการ์ด ส่วนหน้าประวัติไม่ส่งมา (เป็นหน้าประวัติล้วน)
class _TrendBars extends StatelessWidget {
  final List<BillModel?> slots;
  final List<String> labels;
  final List<double> forecastValues;
  final List<String> forecastLabels;
  final double Function(BillModel) selector;
  final Color modeAccent;
  final bool showStacked;
  final double Function(BillModel)? peakUsedSelector;
  final double Function(BillModel)? offPeakUsedSelector;
  final Color touPeakColor;
  final Color touOffPeakColor;
  // true = แท่งเป็นค่าใช้จ่าย (บาท), false = หน่วยที่ใช้ ([unitLabel])
  final bool isCost;
  final String unitLabel;
  final double barWidth;
  final double labelFontSize;

  const _TrendBars({
    required this.slots,
    required this.labels,
    this.forecastValues = const [],
    this.forecastLabels = const [],
    required this.selector,
    required this.modeAccent,
    required this.showStacked,
    required this.peakUsedSelector,
    required this.offPeakUsedSelector,
    required this.touPeakColor,
    required this.touOffPeakColor,
    required this.isCost,
    required this.unitLabel,
    required this.barWidth,
    this.labelFontSize = 10,
  });

  // ระยะห่างเส้นแกน Y เป็นเลขกลม (1, 2, 2.5, 5 × 10^n) ให้ป้ายอ่านง่าย
  static double _niceInterval(double rough) {
    if (rough <= 0) return 1;
    final exp = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final f = rough / exp;
    final nice = f <= 1 ? 1.0 : f <= 2 ? 2.0 : f <= 2.5 ? 2.5 : f <= 5 ? 5.0 : 10.0;
    return nice * exp;
  }

  // ป้ายแกน Y แบบย่อ: 1,500 → "1.5k", 800 → "800"
  static String _axisLabel(double v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k == k.roundToDouble() ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  String _valueText(double v) => isCost
      ? '${NumberFormat('#,##0.00').format(v)} บาท'
      : '${NumberFormat('#,##0.#').format(v)} $unitLabel';

  @override
  Widget build(BuildContext context) {
    final values = slots.map((b) => b == null ? 0.0 : selector(b)).toList();
    // ค่าเฉพาะเดือนที่มีบิลจริง — ช่องว่างไม่นับเป็น 0 ตอนหาสูงสุด/ต่ำสุด
    final present = <double>[
      for (var i = 0; i < slots.length; i++)
        if (slots[i] != null) values[i],
    ];

    final histCount = slots.length;
    final totalCount = histCount + forecastValues.length;
    final allLabels = [...labels, ...forecastLabels];

    // สูงสุด/ต่ำสุด (ไฮไลต์สี) นับเฉพาะเดือนจริง ไม่รวมแท่งคาดการณ์ แต่แกน Y
    // ต้องสูงพอให้แท่งคาดการณ์ไม่ทะลุกรอบ
    final maxVal =
        present.isEmpty ? 0.0 : present.reduce((a, b) => a > b ? a : b);
    final minVal =
        present.isEmpty ? 0.0 : present.reduce((a, b) => a < b ? a : b);
    final forecastMax = forecastValues.isEmpty
        ? 0.0
        : forecastValues.reduce((a, b) => a > b ? a : b);
    final topVal = maxVal > forecastMax ? maxVal : forecastMax;
    final interval = topVal <= 0 ? 2.0 : _niceInterval(topVal * 1.1 / 4);
    final maxY = topVal <= 0 ? 8.0 : (topVal * 1.1 / interval).ceil() * interval;

    final hasVariation = _trendHasVariation(present);
    var peakIndex = -1;
    var lowIndex = -1;
    if (hasVariation) {
      for (var i = 0; i < slots.length; i++) {
        if (slots[i] == null) continue;
        if (peakIndex < 0 && values[i] == maxVal) peakIndex = i;
        if (lowIndex < 0 && values[i] == minVal) lowIndex = i;
      }
    }

    const tooltipStyle = TextStyle(
        color: Colors.white, fontSize: AppTypography.s11, fontWeight: FontWeight.bold);
    const barRadius = BorderRadius.vertical(top: Radius.circular(AppSpacing.v6));

    final chart = BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: interval,
              getTitlesWidget: (value, meta) => Text(
                _axisLabel(value),
                style: TextStyle(fontSize: AppTypography.s10, color: Colors.grey.shade500),
              ),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= allLabels.length) {
                  return const SizedBox.shrink();
                }
                final isForecast = i >= histCount;
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.v4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      allLabels[i],
                      style: TextStyle(
                        fontSize: labelFontSize,
                        color: isForecast ? modeAccent : Colors.grey.shade700,
                        fontWeight: isForecast ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex >= histCount) {
                return BarTooltipItem('คาดการณ์\n${_valueText(rod.toY)}', tooltipStyle);
              }
              final bill = slots[groupIndex];
              if (bill == null) {
                return BarTooltipItem('ไม่มีข้อมูล', tooltipStyle);
              }
              if (showStacked) {
                final peak = peakUsedSelector!(bill);
                final offPeak = offPeakUsedSelector!(bill);
                final hasSplit = peak > 0 || offPeak > 0;
                final unitFmt = NumberFormat('#,##0.#');
                final text = hasSplit
                    ? 'รวม ${_valueText(rod.toY)}\n'
                        'On-Peak ${unitFmt.format(peak)} · '
                        'Off-Peak ${unitFmt.format(offPeak)}'
                    : _valueText(rod.toY);
                return BarTooltipItem(text, tooltipStyle);
              }
              return BarTooltipItem(_valueText(rod.toY), tooltipStyle);
            },
          ),
        ),
        barGroups: List.generate(totalCount, (i) {
          if (i >= histCount) {
            // แท่งคาดการณ์ — โครงประ พื้นจาง แยกจากแท่งเดือนจริง (ทึบ) ชัดเจน
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: forecastValues[i - histCount],
                color: modeAccent.withValues(alpha: 0.10),
                width: barWidth,
                borderRadius: barRadius,
                borderSide: BorderSide(color: modeAccent, width: 1.4),
                borderDashArray: const [4, 3],
              ),
            ]);
          }
          final bill = slots[i];
          if (bill == null) {
            // เดือนที่ไม่มีบิล — แท่งโปร่งใสสูง 0 กันตำแหน่งแท่งอื่นเลื่อน
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                  toY: 0, color: Colors.transparent, width: barWidth),
            ]);
          }
          if (showStacked) {
            final peak = peakUsedSelector!(bill);
            final offPeak = offPeakUsedSelector!(bill);
            final hasSplit = peak > 0 || offPeak > 0;
            if (hasSplit) {
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: peak + offPeak,
                  rodStackItems: [
                    BarChartRodStackItem(0, peak, touPeakColor),
                    BarChartRodStackItem(peak, peak + offPeak, touOffPeakColor),
                  ],
                  width: barWidth,
                  borderRadius: barRadius,
                ),
              ]);
            }
            // บิลที่ไม่มีหน่วยแยก peak/offpeak (เช่น เดือนก่อนสลับ
            // มาเป็นมิเตอร์ TOU) — ไม่มีข้อมูลให้ซ้อน แต่ยังมียอด
            // รวม โชว์เป็นแท่งทึบสีเทาแทนการปล่อยให้เดือนนั้น
            // หายไปจากกราฟเงียบๆ
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i],
                color: Colors.grey.shade400,
                width: barWidth,
                borderRadius: barRadius,
              ),
            ]);
          }
          final barColor = i == peakIndex
              ? _trendPeakColor
              : i == lowIndex
                  ? _trendLowColor
                  : modeAccent;
          return BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: values[i],
              color: barColor,
              width: barWidth,
              borderRadius: barRadius,
            ),
          ]);
        }),
      ),
    );

    if (forecastValues.isEmpty) return chart;

    // เส้น "วันนี้" คั่นระหว่างเดือนจริงกับแท่งคาดการณ์ + ป้าย "คาดการณ์" —
    // BarChart วางกลุ่มแท่งแบบ spaceAround คือแบ่งความกว้างพื้นที่พล็อตเป็น
    // ช่องเท่ากันช่องละ (กว้างพื้นที่พล็อต / จำนวนแท่ง) ดังนั้นรอยต่อระหว่างแท่ง
    // สุดท้ายของประวัติกับแท่งคาดการณ์แรกคือ histCount ช่องจากขอบซ้ายของพื้นที่
    // พล็อต (พื้นที่ซ้ายกันไว้ 34 สำหรับตัวเลขแกน Y, ล่างกันไว้ 22 สำหรับป้ายเดือน
    // ต้องตรงกับ reservedSize ด้านบน)
    return LayoutBuilder(
      builder: (context, constraints) {
        const leftReserved = 34.0;
        const bottomReserved = 22.0;
        final slotWidth = (constraints.maxWidth - leftReserved) / totalCount;
        final dividerX = leftReserved + histCount * slotWidth;
        final plotHeight = constraints.maxHeight - bottomReserved;
        return Stack(
          children: [
            Positioned.fill(child: chart),
            Positioned(
              left: dividerX,
              top: 14,
              width: 1,
              height: plotHeight - 14,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DashedVLinePainter(Colors.grey.shade400),
                ),
              ),
            ),
            Positioned(
              left: dividerX - 48,
              top: 0,
              width: 44,
              child: IgnorePointer(
                child: Text(
                  'วันนี้',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: AppTypography.s9, color: Colors.grey.shade500),
                ),
              ),
            ),
            Positioned(
              left: dividerX + 4,
              top: 0,
              child: IgnorePointer(
                child: Text(
                  'คาดการณ์',
                  style: TextStyle(
                      fontSize: AppTypography.s9,
                      fontWeight: FontWeight.w700,
                      color: modeAccent),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashedVLinePainter extends CustomPainter {
  final Color color;
  const _DashedVLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var y = 0.0;
    while (y < size.height) {
      final end = y + 4 > size.height ? size.height : y + 4;
      canvas.drawLine(Offset(0, y), Offset(0, end), paint);
      y += 7;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedVLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
