part of 'analysis_screen.dart';

// =====================================================================
// กราฟเทรนด์ค่าใช้จ่าย/หน่วยที่ใช้ — ประกอบด้วย
//   1) _TrendChartCard   การ์ดในแท็บวิเคราะห์ โชว์ _cardMonths เดือนล่าสุด
//                        + แท่งประคาดการณ์ 3 เดือนข้างหน้าต่อท้ายในกราฟเดียว
//                        (กดที่หัวการ์ด/"ดูทั้งหมด" เพื่อเปิดหน้าประวัติ)
//   2) _TrendBars        ตัววาดกราฟแท่ง ใช้ร่วมกันทั้งการ์ดและหน้าประวัติ
//   3) _TrendHistoryPage หน้าประวัติเต็ม เลือกดูรายปี (ดรอปดาวน์ ปีนี้/ปีย้อนหลัง)
//                        มีสรุปรวม/เฉลี่ย กราฟ 12 เดือน และรายการรายเดือน
// =====================================================================

// ไฮไลต์แท่งเดือนสูงสุด/ต่ำสุดด้วยสีต่างจากแท่งปกติ ช่วยให้กวาดตาเจอ
// เดือนผิดปกติได้ทันทีโดยไม่ต้องไล่อ่านตัวเลขทีละแท่ง เดือนต่ำสุดใช้สีเขียว
// หลักของแบรนด์ (สื่อว่า "ใช้น้อย = ดี") เดือนสูงสุดใช้ส้มอิฐ
const Color _trendPeakColor = Color(0xFFE2673F);
const Color _trendLowColor = DashboardStyles.primaryGreen;

bool _trendHasVariation(List<double> values) {
  if (values.length < 2) return false;
  final maxVal = values.reduce((a, b) => a > b ? a : b);
  final minVal = values.reduce((a, b) => a < b ? a : b);
  return maxVal != minVal;
}

Widget _trendLegendDot(Color color, String label) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
    ],
  );
}

// คำอธิบายสีแท่ง — แท่งซ้อน TOU โชว์ On-Peak/Off-Peak, นอกนั้นโชว์
// สูงสุด/ต่ำสุด (เฉพาะเมื่อมีความต่างระหว่างเดือนให้ไฮไลต์)
Widget _trendLegend({
  required bool showStacked,
  required bool hasVariation,
  required Color touPeakColor,
  required Color touOffPeakColor,
}) {
  if (showStacked) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _trendLegendDot(touPeakColor, 'On-Peak'),
        const SizedBox(width: 10),
        _trendLegendDot(touOffPeakColor, 'Off-Peak'),
      ],
    );
  }
  if (hasVariation) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _trendLegendDot(_trendPeakColor, 'สูงสุด'),
        const SizedBox(width: 10),
        _trendLegendDot(_trendLowColor, 'ต่ำสุด'),
      ],
    );
  }
  return const SizedBox.shrink();
}

Widget _trendRadio(
    Color accent, String label, bool selected, VoidCallback onTap) {
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
            color: selected ? accent : Colors.grey.shade400,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? accent : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    ),
  );
}

BoxDecoration _trendCardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 6)
      ],
    );

// จุดสีนำหน้าคำอธิบายกราฟ: ทึบ = เดือนจริง (แท่งทึบ), ประ = คาดการณ์ (แท่งประ)
// ใช้สีตามโหมดที่กำลังดู เพื่อให้จับคู่กับแท่งในกราฟได้ทันที
class _LegendSwatch extends StatelessWidget {
  final Color color;
  final bool dashed;
  const _LegendSwatch({required this.color, required this.dashed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: dashed
          ? CustomPaint(painter: _DashedRRectPainter(color))
          : DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  const _DashedRRectPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.7),
      const Radius.circular(3),
    );
    // พื้นจางเท่ากับแท่งคาดการณ์ในกราฟ (alpha 0.10) แล้วเส้นประทับบน
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.10));
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = d + 2.5 > metric.length ? metric.length : d + 2.5;
        canvas.drawPath(metric.extractPath(d, end), stroke);
        d += 4.5;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

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
  // คาดการณ์ล่วงหน้า (ยอดรวมต่อเดือน) ต่อท้ายกราฟเป็นแท่งประ แยกตามโหมด
  // ค่าใช้จ่าย/หน่วย — list ว่าง = ไม่โชว์ส่วนคาดการณ์ (คำนวณที่ _UtilityTab
  // ด้วย forecastNextMonths ตัวเดียวกับการ์ด "คาดการณ์เดือนหน้า")
  final List<double> costForecast;
  final List<double> usedForecast;
  // ข้อมูลน้อยกว่า 3 เดือน → ติดป้ายเตือน "ประมาณการเบื้องต้น"
  final bool forecastLowConfidence;
  // true = คาดการณ์ด้วยเส้นฤดูกาล (รู้ area+meterType) ใช้เลือกข้อความอธิบาย
  final bool usesSeasonalCurve;

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
    this.costForecast = const [],
    this.usedForecast = const [],
    this.forecastLowConfidence = false,
    this.usesSeasonalCurve = false,
  });

  // ---- ตัวช่วยที่ใช้ร่วมกันระหว่างการ์ดกับหน้าประวัติ -------------------

  double Function(BillModel) selectorFor(bool showCost) =>
      showCost ? costSelector : usedSelector;

  // TOU + กำลังดูมุมมอง "หน่วยที่ใช้" (ไม่ใช่ค่าใช้จ่าย) → แท่งซ้อน
  // On-Peak/Off-Peak แทนแท่งทึบสีเดียว ฝั่งค่าใช้จ่ายไม่แยก เพราะ
  // electricityCost เก็บเป็นยอดเดียว ไม่มีราคาแยกตามช่วงเวลาให้ซ้อน
  bool showStackedFor(bool showCost) =>
      !showCost &&
      isTou &&
      peakUsedSelector != null &&
      offPeakUsedSelector != null;

  Color get touPeakColor => unitColor;
  // Off-Peak ใช้สีที่เลือกไว้เฉพาะ ถ้าไม่ได้ส่งมา fallback เป็นเฉดอ่อนของ
  // unitColor แทน
  Color get touOffPeakColorResolved =>
      touOffPeakColor ?? Color.lerp(unitColor, Colors.white, 0.3)!;

  Widget legendFor(bool showCost, List<BillModel> bills) {
    return _trendLegend(
      showStacked: showStackedFor(showCost),
      hasVariation:
          _trendHasVariation(bills.map(selectorFor(showCost)).toList()),
      touPeakColor: touPeakColor,
      touOffPeakColor: touOffPeakColorResolved,
    );
  }

  Widget buildBars({
    required List<BillModel?> slots,
    required List<String> labels,
    required bool showCost,
    required double barWidth,
    double labelFontSize = 9,
    List<double> forecasts = const [],
    List<String> forecastLabels = const [],
  }) {
    return _TrendBars(
      slots: slots,
      labels: labels,
      forecastValues: forecasts,
      forecastLabels: forecastLabels,
      selector: selectorFor(showCost),
      // สีแท่งกราฟจริงตามโหมดที่กำลังดู — ใช้เฉดตรงจากพาเลตที่เลือกไว้
      // ไม่ผ่านการไล่เฉดอัตโนมัติ เพื่อให้สีตรงตาม swatch ที่เลือกเป๊ะๆ
      modeAccent: showCost ? costColor : unitColor,
      showStacked: showStackedFor(showCost),
      peakUsedSelector: peakUsedSelector,
      offPeakUsedSelector: offPeakUsedSelector,
      touPeakColor: touPeakColor,
      touOffPeakColor: touOffPeakColorResolved,
      tooltipSuffix: showCost ? '' : ' $unitLabel',
      barWidth: barWidth,
      labelFontSize: labelFontSize,
    );
  }

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
  // จากบิลทั้งหมดตามเดิม ดูย้อนหลังทั้งหมดได้ที่หน้าประวัติ
  static const int _cardMonths = 6;

  String _emptyMessage(String subject) {
    if (widget.bills.isEmpty) {
      return 'ยังไม่มีข้อมูลบิลของ$subject เลย\nบันทึกบิลเดือนแรกที่หน้าตั้งค่า เพื่อเริ่มเก็บข้อมูล';
    }
    final needed = 2 - widget.bills.length;
    return 'มีข้อมูลแล้ว ${widget.bills.length} เดือน\nบันทึกอีก $needed เดือน จะเริ่มเห็นกราฟแนวโน้มได้';
  }

  void _openHistoryPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _TrendHistoryPage(
          config: widget,
          initialShowCost: _showCost,
        ),
      ),
    );
  }

  void _showForecastInfo() {
    final seasonal = widget.usesSeasonalCurve;
    final touNote = widget.showStackedFor(_showCost);
    showInfoDialog(
      context,
      title: 'ตัวเลขคาดการณ์คำนวณอย่างไร?',
      message: (seasonal
              ? 'ใช้วิธีเดียวกับการ์ด "คาดการณ์เดือนหน้า" ด้านบน '
                  'คือปรับค่าเฉลี่ยล่าสุดของคุณตามรูปแบบฤดูกาลของ'
                  'แต่ละเดือนที่คาดการณ์ ไม่ใช่ลากเส้นตรงเดียวยาว'
                  'ออกไปเรื่อยๆ\n\n'
                  'ยิ่งคาดการณ์ไกลจากปัจจุบันเท่าไร ความไม่แน่นอนก็'
                  'ยังสูงขึ้นอยู่ดี (เหตุการณ์ที่ยังไม่เกิดขึ้นจริง'
                  'ย่อมทายได้ไม่แม่นร้อยเปอร์เซ็นต์) แต่จะแม่นกว่า'
                  'การไม่ปรับตามฤดูกาลเลย'
              : 'ใช้เส้นแนวโน้มเส้นเดียวกับการ์ด "คาดการณ์เดือนหน้า" '
                  'ด้านบน เพียงลากเส้นนั้นต่อไปอีกหลายเดือน\n\n'
                  'ยิ่งคาดการณ์ไกลจากปัจจุบันเท่าไร ความไม่แน่นอนยิ่งสูง'
                  'ขึ้นเรื่อยๆ เพราะไม่ได้ปรับตามฤดูกาลหรือเหตุการณ์ที่'
                  'ยังไม่เกิดขึ้นจริง เหมาะสำหรับดูแนวโน้มคร่าวๆ '
                  'มากกว่าใช้เป็นตัวเลขที่แม่นยำ') +
          (touNote
              ? '\n\nแท่งประเป็นยอดรวมทั้งเดือน ไม่แยก On-Peak/Off-Peak '
                  'เพราะแบบจำลองฤดูกาลสร้างจากยอดหน่วยไฟรวมของมิเตอร์ TOU '
                  'ยังไม่มีเส้นฤดูกาลแยกรายช่วงเวลา การแยกช่วงเองจึงเป็น'
                  'การเดาที่ไม่มีข้อมูลรองรับ'
              : ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allBills = widget.bills;
    final canExpand = allBills.length > _cardMonths;
    final bills =
        canExpand ? allBills.sublist(allBills.length - _cardMonths) : allBills;

    // กราฟโชว์เมื่อมีบิล >= 2 เดือน (เกณฑ์เดิม) — ส่วนคาดการณ์ต่อท้ายตามนั้น
    // ผู้ใช้ที่มีบิลเดียวยังเห็นคาดการณ์เดือนหน้าจากการ์ดด้านบนอยู่
    final hasChart = bills.length >= 2;
    final forecasts = !hasChart
        ? const <double>[]
        : (_showCost ? widget.costForecast : widget.usedForecast);
    final forecastLabels = <String>[
      for (var i = 0; i < forecasts.length; i++)
        () {
          final d = DateTime(bills.last.year, bills.last.month + i + 1, 1);
          return '${d.month}/${d.year % 100}';
        }(),
    ];

    final emptyMessage = _showCost
        ? _emptyMessage(widget.title)
        : _emptyMessage('${widget.unitLabel}ที่ใช้${widget.title}');

    final accent = _showCost ? widget.costColor : widget.unitColor;
    final legendStyle = TextStyle(fontSize: 10.5, color: Colors.grey.shade600);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _trendCardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ส่วนหัวการ์ด — ชื่อการ์ดอยู่ซ้าย ปุ่ม "!" อธิบายวิธีคำนวณอยู่มุมขวาบน
          // กดที่หัวการ์ด (ไอคอน/ชื่อ) เพื่อเปิดหน้าประวัติทั้งหมดได้เช่นกัน ส่วน
          // ตัวกราฟไม่ครอบ เพื่อให้แตะแท่งดู tooltip ได้เหมือนเดิม
          InkWell(
            onTap: canExpand ? _openHistoryPage : null,
            borderRadius: BorderRadius.circular(10),
            child: Row(
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
                  // การ์ดนี้มีทั้งประวัติและคาดการณ์ จึงไม่ใช้คำว่า "ประวัติการใช้"
                  child: Text('ประวัติและคาดการณ์${widget.title}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                if (forecasts.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showForecastInfo,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.accentColor.withValues(alpha: 0.15),
                        ),
                        child: Text('!',
                            style: TextStyle(
                                color: widget.accentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // แถวใต้ชื่อการ์ด เหนือกราฟ: คำอธิบายแท่ง (ซ้าย) กับปุ่มสลับ ค่าใช้จ่าย/หน่วย (ขวา)
          // FittedBox กันคำอธิบายล้นในจอแคบ (ย่อลงแทนการตัดข้อความ)
          Row(
            children: [
              Expanded(
                child: hasChart
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LegendSwatch(color: accent, dashed: false),
                            const SizedBox(width: 5),
                            Text('ย้อนหลัง ${bills.length} เดือน',
                                style: legendStyle),
                            if (forecasts.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              _LegendSwatch(color: accent, dashed: true),
                              const SizedBox(width: 5),
                              Text('คาดการณ์ ${forecasts.length} เดือน',
                                  style: legendStyle),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              _trendRadio(widget.accentColor, 'ค่าใช้จ่าย', _showCost,
                  () => setState(() => _showCost = true)),
              const SizedBox(width: 6),
              _trendRadio(widget.accentColor, widget.unitLabel, !_showCost,
                  () => setState(() => _showCost = false)),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 190,
            child: !hasChart
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
                : widget.buildBars(
                    slots: bills,
                    labels: [
                      for (final b in bills) '${b.month}/${b.year % 100}',
                    ],
                    showCost: _showCost,
                    // 6 + 3 = 9 แท่งในการ์ดแคบ ลดความกว้างแท่งเมื่อมีส่วนคาดการณ์
                    barWidth: forecasts.isEmpty ? 24 : 20,
                    forecasts: forecasts,
                    forecastLabels: forecastLabels,
                  ),
          ),
          if (forecasts.isNotEmpty && widget.forecastLowConfidence) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ประมาณการเบื้องต้น (มีข้อมูล ${widget.bills.length} เดือน) '
                'ยิ่งเดือนไกลยิ่งไม่แน่นอน',
                style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
          // แถวล่างสุด: คำอธิบายสูงสุด/ต่ำสุด (หรือ On-Peak/Off-Peak) ชิดซ้าย
          // และ "ดูทั้งหมด" ชิดขวาล่างของการ์ด
          if (hasChart || canExpand) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: hasChart
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: widget.legendFor(_showCost, bills),
                        )
                      : const SizedBox.shrink(),
                ),
                if (canExpand)
                  InkWell(
                    onTap: _openHistoryPage,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('ดูทั้งหมด',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: widget.accentColor)),
                          Icon(Icons.chevron_right,
                              size: 15, color: widget.accentColor),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

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
  final String tooltipSuffix;
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
    required this.tooltipSuffix,
    required this.barWidth,
    this.labelFontSize = 9,
  });

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
    final maxY = topVal <= 0 ? 8.0 : topVal * 1.25;
    final interval = maxY / 4;

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
        color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold);
    const barRadius = BorderRadius.vertical(top: Radius.circular(6));

    final chart = BarChart(
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
                if (i < 0 || i >= allLabels.length) {
                  return const SizedBox.shrink();
                }
                final isForecast = i >= histCount;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    allLabels[i],
                    style: TextStyle(
                      fontSize: labelFontSize,
                      color: isForecast ? modeAccent : null,
                      fontWeight:
                          isForecast ? FontWeight.w700 : FontWeight.w400,
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
                return BarTooltipItem(
                    'คาดการณ์\n${rod.toY.toStringAsFixed(1)}$tooltipSuffix',
                    tooltipStyle);
              }
              final bill = slots[groupIndex];
              if (bill == null) {
                return BarTooltipItem('ไม่มีข้อมูล', tooltipStyle);
              }
              if (showStacked) {
                final peak = peakUsedSelector!(bill);
                final offPeak = offPeakUsedSelector!(bill);
                final hasSplit = peak > 0 || offPeak > 0;
                final text = hasSplit
                    ? 'รวม ${rod.toY.toStringAsFixed(1)}$tooltipSuffix\n'
                        'On-Peak ${peak.toStringAsFixed(1)} · '
                        'Off-Peak ${offPeak.toStringAsFixed(1)}'
                    : '${rod.toY.toStringAsFixed(1)}$tooltipSuffix';
                return BarTooltipItem(text, tooltipStyle);
              }
              return BarTooltipItem(
                  '${rod.toY.toStringAsFixed(1)}$tooltipSuffix', tooltipStyle);
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
            // บิลเก่าก่อนมีฟิลด์แยก peak/offpeak (หรือมิเตอร์
            // เพิ่งสลับมาเป็น TOU) — ไม่มีข้อมูลให้ซ้อน แต่ยัง
            // มียอดรวม โชว์เป็นแท่งทึบสีเทาแทนการปล่อยให้เดือน
            // นั้นหายไปจากกราฟเงียบๆ
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
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
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
                      fontSize: 9,
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

// =====================================================================
// หน้าประวัติเต็ม — เลือกดูรายปีด้วยดรอปดาวน์ (ปีล่าสุดที่มีข้อมูลเป็นค่าเริ่มต้น,
// ปีที่ตรงกับปัจจุบันติดป้าย "ปีนี้") แต่ละปีโชว์กราฟ ม.ค.-ธ.ค. ครบ 12 ช่อง
// เดือนไหนไม่มีบิลจะเป็นช่องว่าง เทียบข้ามปีได้ตรงเดือนกัน
class _TrendHistoryPage extends StatefulWidget {
  final _TrendChartCard config;
  final bool initialShowCost;

  const _TrendHistoryPage({
    required this.config,
    required this.initialShowCost,
  });

  @override
  State<_TrendHistoryPage> createState() => _TrendHistoryPageState();
}

class _TrendHistoryPageState extends State<_TrendHistoryPage> {
  static const List<String> _monthShort = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  late bool _showCost;
  List<int> _years = const [];
  int _year = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _showCost = widget.initialShowCost;
    // ปีที่มีบิลจริง เรียงใหม่→เก่า (ซ้ายสุด = ปีล่าสุด)
    _years = widget.config.bills.map((b) => b.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (_years.isNotEmpty) _year = _years.first;
  }

  // ดรอปดาวน์เลือกปี (พ.ศ.) — เรียงปีล่าสุดก่อน ปีที่ตรงกับปัจจุบันติดป้าย "ปีนี้"
  Widget _yearDropdown() {
    final accent = widget.config.accentColor;
    final nowYear = DateTime.now().year;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_outlined, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _year,
                isExpanded: true,
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                icon: Icon(Icons.keyboard_arrow_down, color: accent),
                items: [
                  for (final y in _years)
                    DropdownMenuItem<int>(
                      value: y,
                      child: Text(
                        y == nowYear
                            ? 'พ.ศ. ${y + 543} (ปีนี้)'
                            : 'พ.ศ. ${y + 543}',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _year = v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _trendCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _monthRow(BillModel b, NumberFormat costFmt, NumberFormat usedFmt) {
    final cfg = widget.config;
    final cost = '${costFmt.format(cfg.costSelector(b))} บาท';
    final used = '${usedFmt.format(cfg.usedSelector(b))} ${cfg.unitLabel}';

    const primaryStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
    final secondaryStyle = TextStyle(fontSize: 11, color: Colors.grey.shade500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(_monthShort[b.month - 1],
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_showCost ? cost : used, style: primaryStyle),
              const SizedBox(height: 2),
              Text(_showCost ? used : cost, style: secondaryStyle),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final selector = cfg.selectorFor(_showCost);

    final byMonth = <int, BillModel>{
      for (final b in cfg.bills)
        if (b.year == _year) b.month: b,
    };
    final slots = List<BillModel?>.generate(12, (i) => byMonth[i + 1]);
    final present = slots.whereType<BillModel>().toList();
    final values = present.map(selector).toList();
    final total = values.fold<double>(0, (a, b) => a + b);
    final avg = values.isEmpty ? 0.0 : total / values.length;

    final valueUnit = _showCost ? 'บาท' : cfg.unitLabel;
    final costFmt = NumberFormat('#,##0.00');
    final usedFmt = NumberFormat('#,##0.##');
    final valueFmt = _showCost ? costFmt : usedFmt;

    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: AppTopBar(title: 'ประวัติการใช้${cfg.title}'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_years.isNotEmpty) ...[
            _yearDropdown(),
            const SizedBox(height: 12),
          ],
          if (present.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: _statTile(
                      'รวมทั้งปี', '${valueFmt.format(total)} $valueUnit'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statTile(
                      'เฉลี่ยต่อเดือน', '${valueFmt.format(avg)} $valueUnit'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _trendCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('รายเดือน พ.ศ. ${_year + 543}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    _trendRadio(cfg.accentColor, 'ค่าใช้จ่าย', _showCost,
                        () => setState(() => _showCost = true)),
                    const SizedBox(width: 10),
                    _trendRadio(cfg.accentColor, cfg.unitLabel, !_showCost,
                        () => setState(() => _showCost = false)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _showCost
                            ? 'ค่าใช้จ่าย (บาท)'
                            : '${cfg.unitLabel}ที่ใช้',
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade500),
                      ),
                    ),
                    cfg.legendFor(_showCost, present),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 240,
                  child: present.isEmpty
                      ? Center(
                          child: Text(
                            'ไม่มีข้อมูลบิลของปี ${_year + 543}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        )
                      : cfg.buildBars(
                          slots: slots,
                          labels: _monthShort,
                          showCost: _showCost,
                          barWidth: 14,
                          labelFontSize: 8.5,
                        ),
                ),
              ],
            ),
          ),
          if (present.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: _trendCardDecoration(),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('รายละเอียดรายเดือน',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  for (final b in present.reversed) ...[
                    Divider(height: 1, color: Colors.grey.shade200),
                    _monthRow(b, costFmt, usedFmt),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
