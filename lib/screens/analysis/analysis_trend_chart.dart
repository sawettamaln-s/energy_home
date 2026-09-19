part of 'analysis_screen.dart';

// =====================================================================
// การ์ดกราฟเทรนด์ — สลับมุมมองระหว่าง "ค่าใช้จ่าย" กับ "หน่วยที่ใช้" ได้ใน
// การ์ดเดียว ด้วยปุ่มเลือกแบบ radio มุมขวาบน — ต้องเป็น StatefulWidget แยก
// ออกมาจาก _UtilityTab (ซึ่งเป็น StatelessWidget) เพราะต้องจำสถานะว่า
// ผู้ใช้เลือกดูมุมมองไหนอยู่ระหว่างที่ widget อื่นๆ ในหน้าเดียวกัน rebuild
// (เช่น ตอนเลื่อนหน้าจอ)
//
// ในการ์ดโชว์แค่ _cardMonths เดือนล่าสุดให้อ่านง่าย ถ้ามีบิลมากกว่านั้น
// กดที่หัวการ์ด (หรือ "ดูทั้งหมด") จะเปิด bottom sheet แสดงประวัติทุกเดือน
// แบบเลื่อนแนวนอนได้ โดยแกน Y ตรึงอยู่ซ้าย
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

  // จำนวนเดือนที่โชว์ในการ์ด — ข้อมูลย้อนหลังหลายปีถ้าโชว์ทั้งหมดในการ์ด
  // แคบๆ แท่งจะซ้อนกันและป้ายเดือนทับกัน ส่วนตัวเลขเทียบ/คาดการณ์ยังคำนวณ
  // จากบิลทั้งหมดตามเดิม
  static const int _cardMonths = 6;

  // ใน bottom sheet: แต่ละเดือนได้ช่องกว้างคงที่ แล้วให้เลื่อนดูเอา
  static const double _slotWidth = 38;
  static const double _yAxisWidth = 34;

  // ไฮไลต์แท่งเดือนสูงสุด/ต่ำสุดด้วยสีต่างจากแท่งปกติ ช่วยให้กวาดตาเจอ
  // เดือนผิดปกติได้ทันทีโดยไม่ต้องไล่อ่านตัวเลขทีละแท่ง เดือนต่ำสุดใช้สีเขียว
  // หลักของแบรนด์ (สื่อว่า "ใช้น้อย = ดี") เดือนสูงสุดใช้ส้มอิฐ
  static const Color _peakColor = Color(0xFFE2673F);
  static const Color _lowColor = DashboardStyles.primaryGreen;

  double Function(BillModel) get _selector =>
      _showCost ? widget.costSelector : widget.usedSelector;

  // TOU + กำลังดูมุมมอง "หน่วยที่ใช้" (ไม่ใช่ค่าใช้จ่าย) → แท่งซ้อน
  // On-Peak/Off-Peak แทนแท่งทึบสีเดียว ฝั่งค่าใช้จ่ายไม่แยก เพราะ
  // electricityCost เก็บเป็นยอดเดียว ไม่มีราคาแยกตามช่วงเวลาให้ซ้อน
  bool get _showStacked =>
      !_showCost &&
      widget.isTou &&
      widget.peakUsedSelector != null &&
      widget.offPeakUsedSelector != null;

  Color get _touPeakColor => widget.unitColor;
  // Off-Peak ใช้สีที่เลือกไว้เฉพาะ ถ้าไม่ได้ส่งมา fallback เป็นเฉดอ่อนของ
  // unitColor แทน
  Color get _touOffPeakColor =>
      widget.touOffPeakColor ?? Color.lerp(widget.unitColor, Colors.white, 0.3)!;

  String _chartTitle(int months) => _showCost
      ? 'เทรนด์${widget.title} ($months เดือนล่าสุด)'
      : 'เทรนด์${widget.unitLabel}ที่ใช้${widget.title} ($months เดือนล่าสุด)';

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

  bool _hasVariation(List<double> values) {
    if (values.length < 2) return false;
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    return maxVal != minVal;
  }

  // คำอธิบายสีแท่ง — คำนวณจากชุดเดือนที่กำลังโชว์ (การ์ด = 6 เดือน,
  // sheet = ทั้งหมด) เพราะ "สูงสุด/ต่ำสุด" ไฮไลต์ตามชุดที่เห็นอยู่
  Widget _legend(List<BillModel> bills) {
    if (_showStacked) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendDot(_touPeakColor, 'On-Peak'),
          const SizedBox(width: 10),
          _legendDot(_touOffPeakColor, 'Off-Peak'),
        ],
      );
    }
    if (_hasVariation(bills.map(_selector).toList())) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendDot(_peakColor, 'สูงสุด'),
          const SizedBox(width: 10),
          _legendDot(_lowColor, 'ต่ำสุด'),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  // กราฟเปล่าที่วาดเฉพาะแกน Y — ใช้ใน sheet ที่กราฟแท่งเลื่อนได้ ต้องให้
  // maxY/interval และพื้นที่ป้ายเดือนด้านล่าง (reservedSize 22) ตรงกับกราฟ
  // แท่งจริงเป๊ะ เพื่อให้ตัวเลขตรงกับเส้นกริด
  Widget _yAxisOnly(double maxY, double interval) {
    return IgnorePointer(
      child: BarChart(
        BarChartData(
          maxY: maxY,
          minY: 0,
          barGroups: const [],
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: _yAxisWidth,
                interval: interval == 0 ? 1 : interval,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
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
                getTitlesWidget: (value, meta) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // กราฟแท่งของชุดเดือน [bills] — scrollable = false: กราฟเต็มการ์ด (แกน Y
  // ในตัว) / scrollable = true: ใช้ใน bottom sheet เลื่อนแนวนอนได้ แกน Y ตรึง
  Widget _barChart(List<BillModel> bills, {required bool scrollable}) {
    final values = bills.map(_selector).toList();

    final maxVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final minVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxY = maxVal <= 0 ? 8.0 : maxVal * 1.25;
    final interval = maxY / 4;

    final hasVariation = _hasVariation(values);
    final peakIndex = hasVariation ? values.indexOf(maxVal) : -1;
    final lowIndex = hasVariation ? values.indexOf(minVal) : -1;

    // สีแท่งกราฟจริงตามโหมดที่กำลังดู — ใช้เฉดตรงจากพาเลตที่เลือกไว้
    // (ไฟฟ้า = แดง/เหลือง, น้ำ = น้ำเงิน) ไม่ผ่านการไล่เฉดอัตโนมัติ เพื่อให้
    // สีตรงตาม swatch ที่เลือกเป๊ะๆ
    final modeAccent = _showCost ? widget.costColor : widget.unitColor;
    final showStacked = _showStacked;
    final tooltipSuffix = _showCost ? '' : ' ${widget.unitLabel}';
    final barWidth = scrollable ? 20.0 : 24.0;

    final data = BarChartData(
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
        // ใน sheet แกน Y แยกเป็นกราฟเปล่าตรึงซ้ายแล้ว (_yAxisOnly)
        leftTitles: scrollable
            ? const AxisTitles(sideTitles: SideTitles(showTitles: false))
            : AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: interval == 0 ? 1 : interval,
                  getTitlesWidget: (value, meta) => Text(
                    value.toInt().toString(),
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
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
              if (i < 0 || i >= bills.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${bills[i].month}/${bills[i].year % 100}',
                    style: const TextStyle(fontSize: 9)),
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
            if (showStacked) {
              final peak = widget.peakUsedSelector!(bills[groupIndex]);
              final offPeak = widget.offPeakUsedSelector!(bills[groupIndex]);
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
          final offPeak = widget.offPeakUsedSelector!(bills[i]);
          final hasSplit = peak > 0 || offPeak > 0;
          if (hasSplit) {
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: peak + offPeak,
                rodStackItems: [
                  BarChartRodStackItem(0, peak, _touPeakColor),
                  BarChartRodStackItem(peak, peak + offPeak, _touOffPeakColor),
                ],
                width: barWidth,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(6)),
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
              width: barWidth,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ]);
        }
        final barColor = i == peakIndex
            ? _peakColor
            : i == lowIndex
                ? _lowColor
                : modeAccent;
        return BarChartGroupData(x: i, barRods: [
          BarChartRodData(
            toY: values[i],
            color: barColor,
            width: barWidth,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ]);
      }),
    );

    if (!scrollable) return BarChart(data);

    return LayoutBuilder(
      builder: (context, constraints) {
        final scrollAreaWidth = constraints.maxWidth - _yAxisWidth;
        final neededWidth = bills.length * _slotWidth;
        // แท่งน้อย → ยืดเต็มความกว้าง, แท่งเยอะ → กว้างตามจำนวนเดือนแล้วเลื่อนดู
        final contentWidth =
            neededWidth > scrollAreaWidth ? neededWidth : scrollAreaWidth;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _yAxisWidth,
              child: _yAxisOnly(maxY, interval),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // reverse: true = เปิดมาที่ขอบขวา (เดือนล่าสุด) ก่อนเสมอ
                // ผู้ใช้เลื่อนไปทางซ้ายเพื่อดูย้อนหลัง
                reverse: true,
                child: SizedBox(
                  width: contentWidth,
                  child: BarChart(data),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // bottom sheet ประวัติทุกเดือน — มีปุ่มสลับ ค่าใช้จ่าย/หน่วย ของตัวเอง
  // (ใช้ _showCost ตัวเดียวกับการ์ด สลับใน sheet แล้วการ์ดข้างหลังตามด้วย)
  void _openHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final all = widget.bills;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text('ประวัติการใช้${widget.title}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      _radioOption('ค่าใช้จ่าย', _showCost, () {
                        setState(() => _showCost = true);
                        setSheet(() {});
                      }),
                      const SizedBox(width: 10),
                      _radioOption(widget.unitLabel, !_showCost, () {
                        setState(() => _showCost = false);
                        setSheet(() {});
                      }),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ทั้งหมด ${all.length} เดือน • เลื่อนดูย้อนหลัง',
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.grey.shade500),
                        ),
                      ),
                      _legend(all),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 240,
                    child: _barChart(all, scrollable: true),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allBills = widget.bills;
    final canExpand = allBills.length > _cardMonths;
    final bills = canExpand
        ? allBills.sublist(allBills.length - _cardMonths)
        : allBills;
    final values = bills.map(_selector).toList();

    final emptyMessage = _showCost
        ? _emptyMessage(widget.title)
        : _emptyMessage('${widget.unitLabel}ที่ใช้${widget.title}');

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
          // ส่วนหัวการ์ด — กดเพื่อเปิดประวัติทั้งหมด (ปุ่ม radio ข้างในยังกด
          // สลับโหมดได้ตามปกติ เพราะ InkWell ชั้นในรับการกดก่อน) ส่วนตัวกราฟ
          // ไม่ครอบ เพื่อให้แตะแท่งดู tooltip ได้เหมือนเดิม
          InkWell(
            onTap: canExpand ? _openHistorySheet : null,
            borderRadius: BorderRadius.circular(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(Icons.show_chart,
                          color: widget.accentColor, size: 15),
                    ),
                    const SizedBox(width: 8),
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
                      child: Text(_chartTitle(bills.length),
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.grey.shade500)),
                    ),
                    _legend(bills),
                    if (canExpand) ...[
                      const SizedBox(width: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('ดูทั้งหมด',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: widget.accentColor)),
                          Icon(Icons.chevron_right,
                              size: 14, color: widget.accentColor),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
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
                : _barChart(bills, scrollable: false),
          ),
        ],
      ),
    );
  }
}