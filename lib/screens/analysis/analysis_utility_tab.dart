part of 'analysis_screen.dart';

// ==================== Tab อุปกรณ์ ====================
class _ApplianceTab extends StatelessWidget {
  final List<ApplianceModel> appliances;
  final AnalysisService analysisService;

  static const _green = DashboardStyles.primaryGreen;
  final _fmt = NumberFormat('#,##0.00');

  _ApplianceTab({required this.appliances, required this.analysisService});

  @override
  Widget build(BuildContext context) {
    final breakdown = analysisService.applianceBreakdown(appliances);

    if (breakdown.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 160,
                      width: 160,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // โดนัทจำลองจางๆ ให้เห็นรูปทรงว่าพอมีข้อมูลแล้วจะเป็นแบบนี้
                          PieChart(
                            PieChartData(
                              sectionsSpace: 3,
                              centerSpaceRadius: 46,
                              sections: [
                                PieChartSectionData(
                                  value: 40,
                                  color: Colors.grey.shade200,
                                  showTitle: false,
                                  radius: 34,
                                ),
                                PieChartSectionData(
                                  value: 25,
                                  color: Colors.grey.shade100,
                                  showTitle: false,
                                  radius: 34,
                                ),
                                PieChartSectionData(
                                  value: 35,
                                  color: Colors.grey.shade200,
                                  showTitle: false,
                                  radius: 34,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.devices_other,
                              size: 36, color: Colors.grey.shade300),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('ยังไม่มีอุปกรณ์ที่ตั้งตารางการใช้งาน',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    final insights = analysisService.generateApplianceInsights(breakdown);

    // พาเลตใหม่: ยึดโทนเขียวของแบรนด์เป็นหลัก ไล่เฉดเขียวอ่อน-เข้ม สลับกับ
    // สีอุ่นคู่ตรงข้าม (ทอง/ส้ม/น้ำตาล) แทนพาเลตเดิมที่ผสมสีสดจัดหลายโทน
    // ปะปนกัน (ม่วง/ฟ้าสด/ชมพู) ซึ่งดูไม่เป็นชุดเดียวกับสีเขียวหลักของแอป
    // เรียงให้ชิ้นพายที่อยู่ติดกันสลับอุ่น-เย็นชัดเจน แยกออกจากกันง่าย
    final colors = [
      _green, // เขียวหลักของแบรนด์
      const Color(0xFFFFA726), // ส้มทอง
      const Color(0xFF26A69A), // เขียวอมฟ้า (teal)
      const Color(0xFFFFCA28), // เหลืองทอง
      const Color(0xFF8D6E63), // น้ำตาลอบอุ่น
      const Color(0xFF66BB6A), // เขียวอ่อน
      const Color(0xFFD98E5B), // ส้มดิน
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
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
              const Text('สัดส่วนการใช้พลังงาน (kWh/เดือน, ประมาณการ)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              // วงกลม + ป้ายชื่อรายการรอบวง — ป้ายวางด้วย Alignment (ไม่ใช่
              // Positioned ตำแหน่งตายตัว) เพราะไม่รู้ขนาดจริงของป้ายแต่ละ
              // อันล่วงหน้า (ความยาวชื่ออุปกรณ์ไม่เท่ากัน) Alignment ยึด
              // "จุดกึ่งกลาง" ของป้ายที่ตำแหน่งเปอร์เซ็นต์ของกรอบสี่เหลี่ยม
              // ให้เอง ไม่ต้องคำนวณขนาดป้ายเอง
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        // มุมเริ่มที่ 12 นาฬิกา (-90 องศา) ให้คำนวณตำแหน่ง
                        // ป้ายรอบวงตรงกับชิ้นพายจริงเป๊ะๆ
                        startDegreeOffset: -90,
                        sections: List.generate(breakdown.length, (i) {
                          final u = breakdown[i];
                          // ซ่อนตัวเลข % บนชิ้นที่เล็กเกินไป (ไม่งั้นตัวหนังสือ
                          // จะเบียดกันเองหรือล้นออกนอกชิ้นพาย) ไปดู % แทนได้
                          // จากป้ายรอบวง/ตารางอันดับด้านล่าง
                          final showTitle = u.percentOfTotal >= 8;
                          return PieChartSectionData(
                            value: u.kWh,
                            color: colors[i % colors.length],
                            title: showTitle
                                ? '${u.percentOfTotal.toStringAsFixed(0)}%'
                                : '',
                            radius: 56,
                            titleStyle: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          );
                        }),
                      ),
                    ),
                    ..._pieLabelPills(breakdown, colors),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('อันดับอุปกรณ์กินไฟ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        // แสดง top 3 ก่อนเสมอ ถ้ามีมากกว่านั้นค่อยกดขยายดูที่เหลือ
        // (ใช้ widget แยกเพราะ _ApplianceTab เป็น StatelessWidget
        // ไม่มี setState ให้ toggle เอง)
        _ApplianceRankingList(breakdown: breakdown, colors: colors, fmt: _fmt),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => showApplianceEstimateInfoDialog(context),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'เป็นค่าประมาณการ ไม่ใช่ค่าจากมิเตอร์จริง — แตะเพื่อดูรายละเอียด',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ),
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 6)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 16, color: _green),
                    SizedBox(width: 6),
                    Text('ข้อสังเกต',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 10),
                ...insights.map((i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            i.level == InsightLevel.warning
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline,
                            size: 16,
                            color: i.level == InsightLevel.warning
                                ? Colors.orange.shade800
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(i.text,
                                style: const TextStyle(
                                    fontSize: 12.5, height: 1.4)),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // สร้างป้ายชื่อรายการ (ไอคอนจุดสี + ชื่ออุปกรณ์) วางรอบวงกลม โดยอิง
  // ตำแหน่งมุมกึ่งกลางของแต่ละชิ้นพายจริง (คำนวณจาก percentOfTotal
  // สะสมของแต่ละรายการ ตรงกับ startDegreeOffset: -90 ที่ตั้งไว้ในกราฟ)
  // ใช้ Alignment แทน Positioned เพราะไม่ต้องรู้ขนาดป้ายล่วงหน้า — ซ่อน
  // ป้ายของชิ้นที่เล็กเกินไป (<4%) กันป้ายเบียดกันเองรอบวงเวลามีอุปกรณ์
  // เยอะ (ชิ้นเล็กๆ พวกนี้ยังดูรายละเอียดได้จากตารางอันดับด้านล่าง)
  List<Widget> _pieLabelPills(
      List<ApplianceUsage> breakdown, List<Color> colors) {
    const minPercentToLabel = 4.0;
    const radiusFactor = 0.86; // ระยะห่างจากจุดกึ่งกลางออกไปรอบขอบกรอบ
    double cumulative = 0;
    final widgets = <Widget>[];

    for (var i = 0; i < breakdown.length; i++) {
      final u = breakdown[i];
      final sweep = u.percentOfTotal * 3.6;
      if (u.percentOfTotal >= minPercentToLabel) {
        final midAngleDeg = -90 + cumulative * 3.6 + sweep / 2;
        final midAngleRad = midAngleDeg * math.pi / 180;
        widgets.add(
          Align(
            alignment: Alignment(
              math.cos(midAngleRad) * radiusFactor,
              math.sin(midAngleRad) * radiusFactor,
            ),
            child: _PieLabelPill(
              color: colors[i % colors.length],
              label: u.appliance.name,
            ),
          ),
        );
      }
      cumulative += u.percentOfTotal;
    }
    return widgets;
  }
}

// ป้ายชื่อรายการรอบวงกลม — จุดสีตรงกับสีชิ้นพาย + ชื่ออุปกรณ์ ในกล่องมน
// ขอบขาว มีเงาบางๆ (ตาม ref ที่แนบมา) ตัดชื่อที่ยาวเกินด้วย ... กันป้ายเบียด
// ป้ายอื่นหรือล้นออกนอกการ์ด
class _PieLabelPill extends StatelessWidget {
  final Color color;
  final String label;

  const _PieLabelPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE4F2E4),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.18), blurRadius: 5)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// รายการอันดับอุปกรณ์กินไฟ — โชว์แค่ top 3 ก่อนเสมอ (กันไม่ให้ยาวเกินไป
// ถ้ามีอุปกรณ์เยอะ) มีปุ่ม "ดูทั้งหมด" ให้กดขยายดูที่เหลือได้ ถ้ามี ≤ 3
// ตัวอยู่แล้วจะโชว์ครบโดยไม่มีปุ่มเลย
// =====================================================================
class _ApplianceRankingList extends StatefulWidget {
  final List<ApplianceUsage> breakdown;
  final List<Color> colors;
  final NumberFormat fmt;

  const _ApplianceRankingList({
    required this.breakdown,
    required this.colors,
    required this.fmt,
  });

  @override
  State<_ApplianceRankingList> createState() => _ApplianceRankingListState();
}

class _ApplianceRankingListState extends State<_ApplianceRankingList> {
  static const _green = DashboardStyles.primaryGreen;
  static const _collapsedCount = 3;

  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final breakdown = widget.breakdown;
    final hasMore = breakdown.length > _collapsedCount;
    final visibleCount =
        _showAll || !hasMore ? breakdown.length : _collapsedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: Colors.grey.withValues(alpha: 0.06), blurRadius: 4)
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(2.4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(0.9),
              3: FlexColumnWidth(1.3),
            },
            children: [
              // ---- หัวตาราง ----
              TableRow(
                decoration: const BoxDecoration(color: _green),
                children: [
                  _headerCell('อุปกรณ์', alignLeft: true),
                  _headerCell('kWh'),
                  _headerCell('%'),
                  _headerCell('บาท', alignRight: true),
                ],
              ),
              // ---- แถวข้อมูล (แถวสุดท้ายไม่มีเส้นคั่นด้านล่าง) ----
              ...List.generate(visibleCount, (i) {
                final u = breakdown[i];
                final isLast = i == visibleCount - 1;
                return TableRow(
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : Border(
                            bottom: BorderSide(color: Colors.grey.shade100)),
                  ),
                  children: [
                    _nameCell(u.appliance.name,
                        widget.colors[i % widget.colors.length], i),
                    _dataCell(u.kWh.toStringAsFixed(1)),
                    _dataCell('${u.percentOfTotal.toStringAsFixed(0)}%',
                        bold: true, color: _green),
                    _dataCell(widget.fmt.format(u.cost), alignRight: true),
                  ],
                );
              }),
            ],
          ),
        ),
        if (hasMore)
          GestureDetector(
            onTap: () => setState(() => _showAll = !_showAll),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              child: Text(
                _showAll ? 'ย่อรายการ' : 'ดูทั้งหมด (${breakdown.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: _green,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // หัวคอลัมน์ — ตัวหนังสือเทาเล็ก จัดตำแหน่งตามคอลัมน์ (ชื่ออุปกรณ์ชิดซ้าย,
  // บาทชิดขวา, ที่เหลือกึ่งกลาง) ตาม ref
  Widget _headerCell(String label,
      {bool alignLeft = false, bool alignRight = false}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          label,
          textAlign: alignLeft
              ? TextAlign.left
              : (alignRight ? TextAlign.right : TextAlign.center),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // คอลัมน์ชื่ออุปกรณ์ — คงวงกลมสีลำดับ (1,2,3...) แบบเดิมไว้ด้วยกัน แค่ย่อ
  // ขนาดให้พอดีคอลัมน์ตาราง แทนที่จะเป็นการ์ดแยกบรรทัดแบบเดิม
  Widget _nameCell(String name, Color rankColor, int index) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: rankColor.withValues(alpha: 0.15),
              child: Text('${index + 1}',
                  style: TextStyle(
                      color: rankColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // คอลัมน์ตัวเลข (kWh / % / บาท) — กึ่งกลางเป็นค่าเริ่มต้น ยกเว้นคอลัมน์
  // "บาท" ที่ชิดขวาตาม ref, สีเข้ม/หนาได้ถ้าระบุมา (ใช้กับคอลัมน์ %)
  Widget _dataCell(String text, {bool alignRight = false, bool bold = false, Color? color}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          text,
          textAlign: alignRight ? TextAlign.right : TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color ?? Colors.grey.shade800,
          ),
        ),
      ),
    );
  }
}