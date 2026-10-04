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
const Color _trendPeakColor = AppColors.trendPeak;
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
      Text(label, style: TextStyle(fontSize: AppTypography.s9_5, color: Colors.grey.shade600)),
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
    borderRadius: BorderRadius.circular(AppSpacing.v20),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v4, vertical: AppSpacing.v2),
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
              fontSize: AppTypography.s11_5,
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
      borderRadius: BorderRadius.circular(AppSpacing.v14),
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
                borderRadius: BorderRadius.circular(AppSpacing.v3),
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
      const Radius.circular(AppSpacing.v3),
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
  // สีแท่งกราฟ แยกตามโหมด "ค่าใช้จ่าย" กับ "หน่วย/ลบ.ม." — รับมาจาก
  // analysis_screen.dart (ไฟฟ้า = น้ำตาล-ส้ม/ทอง, น้ำ = ฟ้า/น้ำเงิน)
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
  // ด้วย forecastNextMonths แท่งของรอบที่กำลังใช้อยู่ใช้ยอดคาดการณ์สิ้นรอบ)
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
      // สีแท่งกราฟตามโหมดที่กำลังดู — ใช้สีที่ส่งมาตรงๆ ไม่ไล่เฉดอัตโนมัติ
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
  // จากบิลทั้งหมด ดูย้อนหลังทั้งหมดได้ที่หน้าประวัติ
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
    final method = seasonal
        ? 'ใช้วิธีเดียวกับการ์ด "คาดการณ์บิลรอบถัดไป" ด้านล่าง '
            'คือปรับค่าเฉลี่ยล่าสุดของคุณตามรูปแบบฤดูกาลของ'
            'แต่ละเดือนที่คาดการณ์ ไม่ใช่ลากเส้นตรงเดียวยาว'
            'ออกไปเรื่อยๆ\n\n'
            'ยิ่งคาดการณ์ไกลจากปัจจุบันเท่าไร ความไม่แน่นอนก็'
            'ยังสูงขึ้นอยู่ดี (เหตุการณ์ที่ยังไม่เกิดขึ้นจริง'
            'ย่อมทายได้ไม่แม่นร้อยเปอร์เซ็นต์) แต่จะแม่นกว่า'
            'การไม่ปรับตามฤดูกาลเลย'
        : 'ใช้เส้นแนวโน้มเส้นเดียวกับการ์ด "คาดการณ์บิลรอบถัดไป" '
            'ด้านล่าง เพียงลากเส้นนั้นต่อไปอีกหลายเดือน\n\n'
            'ยิ่งคาดการณ์ไกลจากปัจจุบันเท่าไร ความไม่แน่นอนยิ่งสูง'
            'ขึ้นเรื่อยๆ เพราะไม่ได้ปรับตามฤดูกาลหรือเหตุการณ์ที่'
            'ยังไม่เกิดขึ้นจริง เหมาะสำหรับดูแนวโน้มคร่าวๆ '
            'มากกว่าใช้เป็นตัวเลขที่แม่นยำ';
    const currentCycleNote = 'แท่งของบิลรอบที่กำลังใช้อยู่ ใช้ตัวเลขเดียวกับการ์ด '
        '"คาดการณ์ยอดบิลรอบนี้" (คำนวณจากบันทึกมิเตอร์จริงของรอบนี้) '
        'เมื่อบันทึกมิเตอร์ในรอบนี้แล้ว';
    const touText = 'แท่งประเป็นยอดรวมทั้งเดือน ไม่แยก On-Peak/Off-Peak '
        'เพราะแบบจำลองฤดูกาลสร้างจากยอดหน่วยไฟรวมของมิเตอร์ TOU '
        'ยังไม่มีเส้นฤดูกาลแยกรายช่วงเวลา การแยกช่วงเองจึงเป็น'
        'การเดาที่ไม่มีข้อมูลรองรับ';
    showInfoDialog(
      context,
      title: 'ตัวเลขคาดการณ์คำนวณอย่างไร?',
      message: [method, currentCycleNote, if (touNote) touText].join('\n\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allBills = widget.bills;
    final canExpand = allBills.length > _cardMonths;
    final bills =
        canExpand ? allBills.sublist(allBills.length - _cardMonths) : allBills;

    // กราฟโชว์เมื่อมีบิล >= 2 เดือน — ส่วนคาดการณ์ต่อท้ายตามนั้น
    // ผู้ใช้ที่มีบิลเดียวยังเห็นคาดการณ์จากการ์ด "คาดการณ์บิลรอบถัดไป"อยู่
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
    final legendStyle = TextStyle(fontSize: AppTypography.s10_5, color: Colors.grey.shade600);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.v16),
      decoration: _trendCardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ส่วนหัวการ์ด — ชื่อการ์ดอยู่ซ้าย ปุ่ม "!" อธิบายวิธีคำนวณอยู่มุมขวาบน
          // กดที่หัวการ์ด (ไอคอน/ชื่อ) เพื่อเปิดหน้าประวัติทั้งหมดได้เช่นกัน ส่วน
          // ตัวกราฟไม่ครอบ เพื่อให้แตะแท่งดู tooltip ได้ตามปกติ
          InkWell(
            onTap: canExpand ? _openHistoryPage : null,
            borderRadius: BorderRadius.circular(AppSpacing.v10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.v9),
                  ),
                  child: Icon(Icons.show_chart,
                      color: widget.accentColor, size: 15),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // การ์ดนี้มีทั้งประวัติและคาดการณ์ จึงไม่ใช้คำว่า "ประวัติการใช้"
                  child: Text('ประวัติและคาดการณ์${widget.title}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: AppTypography.s13)),
                ),
                if (forecasts.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showForecastInfo,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.v4),
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
                                fontSize: AppTypography.s11,
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
                                        top: Radius.circular(AppSpacing.v6)),
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
                              horizontal: AppSpacing.v16, vertical: AppSpacing.v10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(AppSpacing.v10),
                          ),
                          child: Text(
                            emptyMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: AppTypography.s12, color: Colors.grey),
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v8, vertical: AppSpacing.v4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.v6),
              ),
              child: Text(
                'ประมาณการเบื้องต้น (มีข้อมูล ${widget.bills.length} เดือน) '
                'ยิ่งเดือนไกลยิ่งไม่แน่นอน',
                style: TextStyle(
                    fontSize: AppTypography.s10_5,
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
                    borderRadius: BorderRadius.circular(AppSpacing.v8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.v4, vertical: AppSpacing.v2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('ดูทั้งหมด',
                              style: TextStyle(
                                  fontSize: AppTypography.s10_5,
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
