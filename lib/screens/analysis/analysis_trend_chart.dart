part of 'analysis_screen.dart';

// =====================================================================
// การ์ดกราฟเทรนด์ — สลับมุมมองระหว่าง "ค่าใช้จ่าย" กับ "หน่วยที่ใช้" ได้ใน
// การ์ดเดียว ด้วยปุ่มเลือกแบบ radio มุมขวาบน — ต้องเป็น StatefulWidget แยก
// ออกมาจาก _UtilityTab (ซึ่งเป็น StatelessWidget) เพราะต้องจำสถานะว่า
// ผู้ใช้เลือกดูมุมมองไหนอยู่ระหว่างที่ widget อื่นๆ ในหน้าเดียวกัน rebuild
// (เช่น ตอนเลื่อนหน้าจอ)
class _TrendChartCard extends StatefulWidget {
  final List<BillModel> bills;
  final String title; // 'ค่าไฟฟ้า' / 'ค่าน้ำ' ใช้ตั้งชื่อกราฟฝั่งค่าใช้จ่าย
  final String unitLabel; // 'หน่วย' / 'ลบ.ม.' ใช้เป็น label ปุ่มฝั่งหน่วย
  final double Function(BillModel) costSelector;
  final double Function(BillModel) usedSelector;
  final Color accentColor;
  // สีแท่งกราฟจริง แยกตามโหมด "ค่าใช้จ่าย" กับ "หน่วย/ลบ.ม." — รับเฉดจาก
  // พาเลตที่เลือกไว้ต่อยูทิลิตี้ตรงๆ (ไฟฟ้า = แดง/เหลือง, น้ำ = น้ำเงิน)
  final Color costColor;
  final Color unitColor;
  // TOU เท่านั้น — สี Off-Peak ของแท่งซ้อน ถ้าไม่ส่งมาจะ fallback เป็นเฉด
  // อ่อนของ unitColor แทน
  final Color? touOffPeakColor;
  // TOU เท่านั้น — ดู _UtilityTab ด้านบนสำหรับที่มา
  final bool isTou;
  final double Function(BillModel)? peakUsedSelector;
  final double Function(BillModel)? offPeakUsedSelector;

  const _TrendChartCard({
    required this.bills,
    required this.title,
    required this.unitLabel,
    required this.costSelector,
    required this.usedSelector,
    required this.accentColor,
    required this.costColor,
    required this.unitColor,
    this.touOffPeakColor,
    this.isTou = false,
    this.peakUsedSelector,
    this.offPeakUsedSelector,
  });

  @override
  State<_TrendChartCard> createState() => _TrendChartCardState();
}

class _TrendChartCardState extends State<_TrendChartCard> {
  // true = โชว์กราฟค่าใช้จ่าย (บาท), false = โชว์กราฟหน่วยที่ใช้ — เริ่มที่
  // ค่าใช้จ่ายเป็นค่าเริ่มต้นเสมอ เพราะเป็นข้อมูลที่มีครบทุกเดือนแน่นอนกว่า
  // (หน่วยอาจเป็น 0 ในเดือนแรกสุดที่ไม่มี record ก่อนหน้าให้คำนวณ delta)
  bool _showCost = true;

  String _emptyMessage(String subject) {
    if (widget.bills.isEmpty) {
      return 'ยังไม่มีข้อมูลบิลของ$subject เลย\nบันทึกบิลเดือนแรกที่หน้าตั้งค่า เพื่อเริ่มเก็บข้อมูล';
    }
    final needed = 2 - widget.bills.length;
    return 'มีข้อมูลแล้ว ${widget.bills.length} เดือน\nบันทึกอีก $needed เดือน จะเริ่มเห็นกราฟแนวโน้มได้';
  }

  Widget _radioOption(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 15,
              color: selected ? widget.accentColor : Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? widget.accentColor : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bills = widget.bills;
    final values = bills
        .map(_showCost ? widget.costSelector : widget.usedSelector)
        .toList();

    final maxVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final minVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxY = maxVal <= 0 ? 8.0 : maxVal * 1.25;
    final interval = maxY / 4;

    // ไฮไลต์แท่งเดือนสูงสุด/ต่ำสุดด้วยสีต่างจากแท่งปกติ ช่วยให้กวาดตาเจอ
    // เดือนผิดปกติได้ทันทีโดยไม่ต้องไล่อ่านตัวเลขทีละแท่ง
    final hasVariation = values.length >= 2 && maxVal != minVal;
    final peakIndex = hasVariation ? values.indexOf(maxVal) : -1;
    final lowIndex = hasVariation ? values.indexOf(minVal) : -1;
    // ไฮไลต์เดือนสูงสุด/ต่ำสุดของทุกยูทิลิตี้ (แยกจากพาเลตสีประจำยูทิลิตี้
    // ให้ยังโดดเด่นเห็นชัดไม่ว่าจะเป็นแท็บไหน) เดือนต่ำสุดใช้สีเขียวหลักของ
    // แบรนด์ (สื่อว่า "ใช้น้อย = ดี") เดือนสูงสุดใช้ส้มอิฐ
    const peakColor = Color(0xFFE2673F); // ส้มอิฐ — เดือนใช้สูงสุด
    const lowColor = DashboardStyles.primaryGreen; // เขียวหลักของแบรนด์ — เดือนใช้ต่ำสุด

    // สีแท่งกราฟจริงตามโหมดที่กำลังดู — ใช้เฉดตรงจากพาเลตที่เลือกไว้
    // (ไฟฟ้า = แดง/เหลือง, น้ำ = น้ำเงิน) ไม่ผ่านการไล่เฉดอัตโนมัติ เพื่อให้
    // สีตรงตาม swatch ที่เลือกเป๊ะๆ
    final modeAccent = _showCost ? widget.costColor : widget.unitColor;

    // TOU + กำลังดูมุมมอง "หน่วยที่ใช้" (ไม่ใช่ค่าใช้จ่าย) → แท่งซ้อน
    // On-Peak/Off-Peak แทนแท่งทึบสีเดียว ฝั่งค่าใช้จ่ายไม่แยก เพราะ
    // electricityCost เก็บเป็นยอดเดียว ไม่มีราคาแยกตามช่วงเวลาให้ซ้อน
    final showStacked = !_showCost &&
        widget.isTou &&
        widget.peakUsedSelector != null &&
        widget.offPeakUsedSelector != null;
    // Off-Peak ใช้สีที่เลือกไว้เฉพาะ (เช่น เหลืองอ่อนคู่กับเหลืองเข้มของ
    // On-Peak) ถ้าไม่ได้ส่งมา fallback เป็นเฉดอ่อนของ unitColor แทน
    final touPeakColor = widget.unitColor;
    final touOffPeakColor =
        widget.touOffPeakColor ?? Color.lerp(widget.unitColor, Colors.white, 0.3)!;


    final chartTitle = _showCost
        ? 'เทรนด์${widget.title} (${bills.length} เดือนล่าสุด)'
        : 'เทรนด์${widget.unitLabel}ที่ใช้${widget.title} '
            '(${bills.length} เดือนล่าสุด)';
    final emptyMessage = _showCost
        ? _emptyMessage(widget.title)
        : _emptyMessage('${widget.unitLabel}ที่ใช้${widget.title}');
    final tooltipSuffix = _showCost ? '' : ' ${widget.unitLabel}';

    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('ประวัติการใช้${widget.title}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              _radioOption('ค่าใช้จ่าย', _showCost,
                  () => setState(() => _showCost = true)),
              const SizedBox(width: 10),
              _radioOption(widget.unitLabel, !_showCost,
                  () => setState(() => _showCost = false)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(chartTitle,
                    style: TextStyle(
                        fontSize: 10.5, color: Colors.grey.shade500)),
              ),
              if (showStacked) ...[
                _legendDot(touPeakColor, 'On-Peak'),
                const SizedBox(width: 10),
                _legendDot(touOffPeakColor, 'Off-Peak'),
              ] else if (hasVariation) ...[
                _legendDot(peakColor, 'สูงสุด'),
                const SizedBox(width: 10),
                _legendDot(lowColor, 'ต่ำสุด'),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: values.length < 2
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: BarChart(
                            BarChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              barTouchData: BarTouchData(enabled: false),
                              maxY: 8,
                              barGroups: List.generate(6, (i) {
                                const demo = [3.0, 5.0, 3.5, 6.0, 4.5, 6.5];
                                return BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                    toY: demo[i],
                                    color: Colors.grey.shade300,
                                    width: 18,
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6)),
                                  ),
                                ]);
                              }),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            emptyMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  )
                : BarChart(
                    BarChartData(
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: interval == 0 ? 1 : interval,
                        getDrawingHorizontalLine: (v) =>
                            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            interval: interval == 0 ? 1 : interval,
                            getTitlesWidget: (value, meta) => Text(
                              value.toInt().toString(),
                              style: TextStyle(
                                  fontSize: 9, color: Colors.grey.shade500),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= bills.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                    '${bills[i].month}/${bills[i].year % 100}',
                                    style: const TextStyle(fontSize: 9)),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (showStacked) {
                              final peak =
                                  widget.peakUsedSelector!(bills[groupIndex]);
                              final offPeak = widget
                                  .offPeakUsedSelector!(bills[groupIndex]);
                              final hasSplit = peak > 0 || offPeak > 0;
                              final text = hasSplit
                                  ? 'รวม ${rod.toY.toStringAsFixed(1)}$tooltipSuffix\n'
                                      'On-Peak ${peak.toStringAsFixed(1)} · '
                                      'Off-Peak ${offPeak.toStringAsFixed(1)}'
                                  : '${rod.toY.toStringAsFixed(1)}$tooltipSuffix';
                              return BarTooltipItem(
                                text,
                                const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              );
                            }
                            return BarTooltipItem(
                              '${rod.toY.toStringAsFixed(1)}$tooltipSuffix',
                              const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                      ),
                      barGroups: List.generate(values.length, (i) {
                        if (showStacked) {
                          final peak = widget.peakUsedSelector!(bills[i]);
                          final offPeak =
                              widget.offPeakUsedSelector!(bills[i]);
                          final hasSplit = peak > 0 || offPeak > 0;
                          if (hasSplit) {
                            return BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: peak + offPeak,
                                rodStackItems: [
                                  BarChartRodStackItem(0, peak, touPeakColor),
                                  BarChartRodStackItem(peak, peak + offPeak,
                                      touOffPeakColor),
                                ],
                                width: 18,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6)),
                              ),
                            ]);
                          }
                          // บิลเก่าก่อนมีฟิลด์แยก peak/offpeak (หรือมิเตอร์
                          // เพิ่งสลับมาเป็น TOU) — ไม่มีข้อมูลให้ซ้อน แต่ยัง
                          // มียอดรวม โชว์เป็นแท่งทึบสีเทาแทนการปล่อยให้เดือน
                          // นั้นหายไปจากกราฟเงียบๆ
                          return BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: values[i],
                              color: Colors.grey.shade400,
                              width: 18,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                            ),
                          ]);
                        }
                        final barColor = i == peakIndex
                            ? peakColor
                            : i == lowIndex
                                ? lowColor
                                : modeAccent;
                        return BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: values[i],
                            color: barColor,
                            width: 18,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6)),
                          ),
                        ]);
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
      ],
    );
  }
}