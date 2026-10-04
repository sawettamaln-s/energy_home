part of 'analysis_screen.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v12),
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
                borderRadius: BorderRadius.circular(AppSpacing.v12),
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
                            fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: _trendCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style:
                    const TextStyle(fontSize: AppTypography.s15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _monthRow(BillModel b, NumberFormat costFmt, NumberFormat usedFmt) {
    final cfg = widget.config;
    final cost = '${costFmt.format(cfg.costSelector(b))} บาท';
    final used = '${usedFmt.format(cfg.usedSelector(b))} ${cfg.unitLabel}';

    const primaryStyle = TextStyle(fontSize: AppTypography.s13, fontWeight: FontWeight.w700);
    final secondaryStyle = TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.v10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(_monthShort[b.month - 1],
                style:
                    const TextStyle(fontSize: AppTypography.s13, fontWeight: FontWeight.w600)),
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
        padding: const EdgeInsets.all(AppSpacing.v16),
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
            padding: const EdgeInsets.all(AppSpacing.v16),
            decoration: _trendCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('รายเดือน พ.ศ. ${_year + 543}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: AppTypography.s13)),
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
                            fontSize: AppTypography.s10_5, color: Colors.grey.shade500),
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
                                fontSize: AppTypography.s12, color: Colors.grey),
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v16, vertical: AppSpacing.v8),
              decoration: _trendCardDecoration(),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.v8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('รายละเอียดรายเดือน',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: AppTypography.s13)),
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
