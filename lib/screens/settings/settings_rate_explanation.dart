part of 'settings_screen.dart';

// ==================== อธิบายอัตราค่าไฟฟ้า / น้ำ ====================
// หน้าแสดงอัตราที่แอปใช้คิดให้ผู้ใช้จริง (ตามพื้นที่/ประเภทมิเตอร์/ประเภทอัตรา
// ในโปรไฟล์) ไม่มีการบันทึกข้อมูล ค่า Ft ดึงสดจาก app_config/electricity_rates
// ลำดับ: สรุปอัตราของฉัน -> ตารางอัตรา -> บิลคิดอย่างไร -> ข้อควรรู้ -> แหล่งอ้างอิง
class RateExplanationScreen extends StatefulWidget {
  final String area; // 'bangkok' (MEA/MWA) หรือ 'province' (PEA/PWA)
  final String meterType; // 'normal' หรือ 'tou'
  final String tariff; // ประเภทอัตราของมิเตอร์ปกติ (UserModel.electricityTariff)
  // ตัวโหลดค่า Ft (ไม่ส่ง = EnergyCalculator.getFtInfo ตัวเดียวกับที่คิดบิลจริง)
  final Future<FtInfo> Function()? ftLoader;

  const RateExplanationScreen({
    super.key,
    required this.area,
    required this.meterType,
    required this.tariff,
    this.ftLoader,
  });

  @override
  State<RateExplanationScreen> createState() => _RateExplanationScreenState();
}

class _RateExplanationScreenState extends State<RateExplanationScreen> {
  bool _showWater = false;
  FtInfo? _ft;

  bool get _isBangkok => widget.area == 'bangkok';
  bool get _isTou => widget.meterType == 'tou';
  bool get _isSmall => widget.tariff == EnergyCalculator.tariffSmall;
  Color get _accent => _showWater ? AppColors.waterBorder : AppColors.electricityBorder;

  @override
  void initState() {
    super.initState();
    _loadFt();
  }

  Future<void> _loadFt() async {
    final ft = await (widget.ftLoader ?? EnergyCalculator.getFtInfo)();
    if (mounted) setState(() => _ft = ft);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: const AppTopBar(title: 'อัตราค่าไฟฟ้า / น้ำ'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v16, AppSpacing.v32),
        children: [
          _utilityToggle(),
          const SizedBox(height: AppSpacing.v12),
          FadeSlideIn(
            key: ValueKey(_showWater),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _showWater ? _waterContent() : _electricityContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _utilityToggle() {
    Widget option(String label, IconData icon, bool water) {
      final selected = _showWater == water;
      final color = water ? AppColors.waterBorder : AppColors.electricityBorder;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showWater = water),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.v8),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm - 2),
              boxShadow: selected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? color : Colors.grey.shade500),
                const SizedBox(width: AppSpacing.v4),
                Text(label,
                    style: TextStyle(
                        fontSize: AppTypography.s13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? color : Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.v3),
      decoration: BoxDecoration(
        color: Colors.grey.shade200.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          option('ไฟฟ้า', Icons.bolt_rounded, false),
          option('น้ำ', Icons.water_drop_rounded, true),
        ],
      ),
    );
  }

  // ==================== ส่วนประกอบร่วม ====================

  // หัวการ์ด: ชื่อ + คำอธิบายสั้น + ปุ่ม ⓘ (ถ้ามีรายละเอียดเพิ่ม)
  Widget _cardTitle(String title, {String? subtitle, String? infoTitle, String? infoMessage}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: AppTypography.s15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.v2),
                Text(subtitle, style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
              ],
            ],
          ),
        ),
        if (infoTitle != null && infoMessage != null)
          IconButton(
            tooltip: infoTitle,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.info_outline, size: 20, color: Colors.grey.shade600),
            onPressed: () => showInfoDialog(context, title: infoTitle, message: infoMessage),
          ),
      ],
    );
  }

  // การ์ด "อัตราที่แอปใช้คิดให้คุณ": ผู้ให้บริการ + ประเภท + ตัวเลขหลัก
  Widget _summaryCard({
    required IconData icon,
    required String provider,
    required String plan,
    required List<({String label, String value, String unit})> facts,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: _accent, size: 40),
              const SizedBox(width: AppSpacing.v12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('อัตราที่แอปใช้คิดให้คุณ',
                        style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                    Text(provider,
                        style: const TextStyle(
                            fontSize: AppTypography.s15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v10, vertical: AppSpacing.v6),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Text(plan,
                style: TextStyle(fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600, color: _accent)),
          ),
          const SizedBox(height: AppSpacing.v12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, f) in facts.indexed) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 34,
                    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.v8),
                    color: Colors.grey.shade200,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
                      const SizedBox(height: AppSpacing.v2),
                      Text(f.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: AppTypography.s15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      Text(f.unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ตารางอัตรา: หัวคอลัมน์ + แถวสลับสี — group = หัวข้อย่อยคั่นกลางตาราง
  Widget _rateTable(List<({String range, String price, String? group})> rows,
      {String rangeHeader = 'จำนวนหน่วยที่ใช้', String priceHeader = 'บาท/หน่วย'}) {
    final headerStyle =
        TextStyle(fontSize: AppTypography.s12, fontWeight: FontWeight.w600, color: Colors.grey.shade700);
    var alt = false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Column(
          children: [
            Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v12, vertical: AppSpacing.v8),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(rangeHeader, style: headerStyle)),
                  Expanded(flex: 2, child: Text(priceHeader, textAlign: TextAlign.right, style: headerStyle)),
                ],
              ),
            ),
            for (final r in rows) ...[
              if (r.group != null)
                Container(
                  width: double.infinity,
                  color: _accent.withValues(alpha: 0.06),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.v12, AppSpacing.v8, AppSpacing.v12, AppSpacing.v6),
                  child: Text(r.group!,
                      style: TextStyle(fontSize: AppTypography.s12, fontWeight: FontWeight.w600, color: _accent)),
                ),
              Builder(builder: (context) {
                alt = !alt;
                return Container(
                  color: alt ? Colors.white : Colors.grey.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v12, vertical: AppSpacing.v8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(r.range,
                            style: const TextStyle(fontSize: AppTypography.s13, color: AppColors.textDark)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(r.price,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: AppTypography.s13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  // ขั้นตอนคิดบิลแบบเลขลำดับ — detail คือสูตรสั้นๆ ใต้ชื่อขั้น
  Widget _steps(List<({String title, String detail, Widget? extra})> steps) {
    return Column(
      children: [
        for (final (i, s) in steps.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.v12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Text('${i + 1}',
                      style: TextStyle(fontSize: AppTypography.s12, fontWeight: FontWeight.w700, color: _accent)),
                ),
                const SizedBox(width: AppSpacing.v10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title,
                          style: const TextStyle(
                              fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                      const SizedBox(height: AppSpacing.v2),
                      Text(s.detail,
                          style: TextStyle(fontSize: AppTypography.s12_5, height: 1.45, color: Colors.grey.shade700)),
                      if (s.extra != null) s.extra!,
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ข้อความแบบมีจุดนำ ใช้ในการ์ดข้อควรรู้
  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.v8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.v6, right: AppSpacing.v8),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: Colors.grey.shade500, shape: BoxShape.circle),
              ),
            ),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: Colors.grey.shade800)),
            ),
          ],
        ),
      );

  Widget _sources(List<String> sources) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v4, AppSpacing.v16, AppSpacing.v4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined, size: 15, color: Colors.grey.shade600),
              const SizedBox(width: AppSpacing.v6),
              Expanded(
                child: Text('ตรวจกับประกาศทางการล่าสุดเมื่อ 3 ต.ค. 2569',
                    style: TextStyle(
                        fontSize: AppTypography.s12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              ),
            ],
          ),
          for (final s in sources)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.v4, left: AppSpacing.v20),
              child: Text(s, style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
            ),
        ],
      ),
    );
  }

  String _rate4(double v) => v.toStringAsFixed(4);
  String _rate2(double v) => v.toStringAsFixed(2);

  // แถวตารางอัตราจากขั้นบันไดใน TariffTables — ช่วงหน่วย ("1 - 30", "201 ขึ้นไป")
  // สร้างจากตารางเดียวกับที่ใช้คิดเงิน [groups] = หัวกลุ่มเหนือแถวลำดับนั้น
  List<({String range, String price, String? group})> _tierRows(
    List<TariffTier> tiers,
    String Function(double) price, {
    Map<int, String> groups = const {},
  }) {
    final fmt = NumberFormat('#,##0');
    final rows = <({String range, String price, String? group})>[];
    var lower = 0.0;
    for (var i = 0; i < tiers.length; i++) {
      final t = tiers[i];
      final from = fmt.format(lower + 1);
      final range = t.upTo == double.infinity ? '$from ขึ้นไป' : '$from - ${fmt.format(t.upTo)}';
      rows.add((range: range, price: price(t.rate), group: groups[i]));
      lower = t.upTo;
    }
    return rows;
  }

  // ==================== ไฟฟ้า ====================

  List<Widget> _electricityContent() {
    final area = widget.area;
    final smallCode = EnergyCalculator.tariffCode(EnergyCalculator.tariffSmall, area);
    final standardCode = EnergyCalculator.tariffCode(EnergyCalculator.tariffStandard, area);
    final touCode = EnergyCalculator.touCode(area);
    final serviceFee = _isTou
        ? TariffTables.touServiceFee
        : _isSmall
            ? TariffTables.electricitySmallServiceFee
            : TariffTables.electricityStandardServiceFee;
    final ftOutdated = _ft != null && EnergyCalculator.isFtOutdated(_ft!.effectiveFrom, DateTime.now());
    final provider = _isBangkok ? 'การไฟฟ้านครหลวง (MEA)' : 'การไฟฟ้าส่วนภูมิภาค (PEA)';
    final plan = _isTou
        ? 'มิเตอร์ TOU · ประเภท $touCode'
        : 'มิเตอร์ปกติ · ประเภท ${_isSmall ? '$smallCode ใช้ไม่เกิน 150 หน่วย/เดือน' : '$standardCode ใช้เกิน 150 หน่วย/เดือน'}';

    final rows = <({String range, String price, String? group})>[
      if (_isTou) ...[
        (range: 'On-Peak\nจ.-ศ. 09:00-22:00 น.', price: _rate4(TariffTables.touPeakRate), group: null),
        (
          range: 'Off-Peak\nนอกเวลาข้างต้น ส.-อา. และวันหยุดราชการ',
          price: _rate4(TariffTables.touOffPeakRate),
          group: null
        ),
      ] else
        ..._tierRows(_isSmall ? TariffTables.electricitySmall : TariffTables.electricityStandard, _rate4),
    ];

    Widget ftDetail() {
      if (_ft == null) return const SizedBox.shrink();
      final from = _ft!.effectiveFrom;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (from != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.v4),
              child: Text('งวดที่เริ่ม ${from.day} ${thaiMonths[from.month - 1]} ${from.year + 543}',
                  style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
            ),
          // งวดที่ตั้งไว้เก่ากว่า 4 เดือน = ยังไม่ได้อัปเดตงวดใหม่ ยอดอาจคลาด
          if (ftOutdated)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.v8),
              padding: const EdgeInsets.all(AppSpacing.v8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: AppColors.warningBorder),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warningIcon),
                  SizedBox(width: AppSpacing.v6),
                  Expanded(
                    child: Text(
                      'ค่า Ft งวดใหม่อาจยังไม่ได้อัปเดตในแอป ยอดค่าไฟที่คำนวณอาจคลาดจากบิลจริงเล็กน้อยค่ะ',
                      style: TextStyle(fontSize: AppTypography.s12, color: AppColors.warningText),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return [
      _summaryCard(
        icon: Icons.bolt_rounded,
        provider: provider,
        plan: plan,
        facts: [
          (label: 'ค่าบริการ', value: _rate2(serviceFee), unit: 'บาท/เดือน'),
          (label: 'ค่า Ft', value: _ft == null ? '...' : _rate4(_ft!.rate), unit: 'บาท/หน่วย'),
          (label: 'ภาษีมูลค่าเพิ่ม', value: '7%', unit: 'ของยอดรวม'),
        ],
      ),
      const SizedBox(height: AppSpacing.v12),
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.v16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle(
              _isTou ? 'อัตราค่าไฟ TOU' : 'ตารางอัตราค่าไฟ',
              subtitle: _isTou ? 'ราคาคงที่ตามช่วงเวลา ไม่ขึ้นกับจำนวนหน่วย' : 'คิดแบบขั้นบันได ยิ่งใช้มาก หน่วยท้ายๆ ยิ่งแพง',
              infoTitle: _isTou ? 'อัตรา TOU คืออะไร' : 'อัตราขั้นบันไดคืออะไร',
              infoMessage: _isTou
                  ? 'มิเตอร์ TOU คิดค่าไฟตามช่วงเวลาที่ใช้ แบ่งเป็น On-Peak (ไฟแพง) และ Off-Peak (ไฟถูก) '
                      'ราคาต่อหน่วยคงที่ตลอดแต่ละช่วง ใช้ไฟช่วง Off-Peak มากเท่าไรก็ยิ่งประหยัด'
                  : 'หน่วยแรกๆ ของเดือนราคาต่ำ เมื่อใช้เกินแต่ละขั้น หน่วยที่เกินจะคิดราคาขั้นถัดไป '
                      'เช่น ใช้ 250 หน่วย: 200 หน่วยแรกคิดราคาขั้นที่ 1 และอีก 50 หน่วยคิดราคาขั้นที่ 2 '
                      'ไม่ได้คิดราคาเดียวทั้งบิล',
            ),
            const SizedBox(height: AppSpacing.v12),
            _rateTable(rows, rangeHeader: _isTou ? 'ช่วงเวลา' : 'จำนวนหน่วยที่ใช้'),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.v12),
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.v16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle('บิลค่าไฟคิดอย่างไร',
                subtitle: 'ลำดับเดียวกับที่แอปใช้ประมาณยอดให้คุณ',
                infoTitle: 'ค่า Ft คืออะไร',
                infoMessage: 'ค่า Ft (ค่าไฟฟ้าผันแปร) ปรับขึ้น-ลงตามต้นทุนเชื้อเพลิงและค่าซื้อไฟของการไฟฟ้า '
                    'คณะกรรมการกำกับกิจการพลังงาน (กกพ.) ประกาศใหม่ทุก 4 เดือน (งวด ม.ค.-เม.ย., พ.ค.-ส.ค., ก.ย.-ธ.ค.) '
                    'แอปดึงค่า Ft ที่ผู้ดูแลระบบตั้งไว้มาคำนวณให้อัตโนมัติ ไม่ต้องกรอกเอง'),
            const SizedBox(height: AppSpacing.v14),
            _steps([
              (
                title: 'ค่าพลังงานไฟฟ้า',
                detail: _isTou
                    ? 'หน่วย On-Peak × อัตรา On-Peak + หน่วย Off-Peak × อัตรา Off-Peak'
                    : 'หน่วยที่ใช้ในแต่ละขั้น × อัตราของขั้นนั้น ตามตารางด้านบน',
                extra: null
              ),
              (title: 'บวกค่าบริการรายเดือน', detail: '${_rate2(serviceFee)} บาท ทุกเดือน แม้ไม่ได้ใช้ไฟ', extra: null),
              (
                title: 'บวกค่า Ft',
                detail: _ft == null
                    ? 'หน่วยที่ใช้ทั้งหมด × ค่า Ft'
                    : 'หน่วยที่ใช้ทั้งหมด × ${_rate4(_ft!.rate)} บาท',
                extra: ftDetail()
              ),
              (title: 'บวกภาษีมูลค่าเพิ่ม 7%', detail: 'คิดจากยอดรวมข้อ 1-3 ได้เป็นยอดที่ต้องจ่าย', extra: null),
            ]),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.v12),
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.v16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle('ประเภทอัตราค่าไฟบ้านอยู่อาศัย',
                subtitle: 'ดูประเภทของบ้านคุณได้จากใบแจ้งหนี้ค่าไฟ',
                infoTitle: 'การเปลี่ยนประเภทอัตรา',
                infoMessage: 'มิเตอร์ไม่เกิน 5 แอมแปร์: ใช้เกิน 150 หน่วยติดต่อกัน 3 เดือน เดือนถัดไปเป็นประเภท '
                    '$standardCode และใช้ไม่เกิน 150 หน่วยติดต่อกัน 3 เดือน กลับเป็นประเภท $smallCode '
                    'ถ้าบิลของคุณเข้าเงื่อนไข แอปจะแจ้งให้ตรวจค่ะ\n\n'
                    'เปลี่ยนประเภทให้ตรงใบแจ้งหนี้ได้ที่ ตั้งค่า > ประเภทอัตราค่าไฟ'),
            const SizedBox(height: AppSpacing.v4),
            _tariffOption(
              code: smallCode,
              title: 'ใช้ไม่เกิน 150 หน่วย/เดือน',
              detail: 'มิเตอร์ไม่เกิน 5 แอมแปร์ ค่าบริการ ${_rate2(TariffTables.electricitySmallServiceFee)} บาท/เดือน',
              inUse: !_isTou && _isSmall,
            ),
            _tariffOption(
              code: standardCode,
              title: 'ใช้เกิน 150 หน่วย/เดือน',
              detail: 'บ้านส่วนใหญ่อยู่ประเภทนี้ ค่าบริการ '
                  '${_rate2(TariffTables.electricityStandardServiceFee)} บาท/เดือน',
              inUse: !_isTou && !_isSmall,
            ),
            _tariffOption(
              code: touCode,
              title: 'TOU คิดตามช่วงเวลา',
              detail: 'ต้องติดตั้งมิเตอร์ TOU แอปใช้อัตราแรงดันต่ำกว่า ${_isBangkok ? '12' : '22'} kV ของบ้านทั่วไป',
              inUse: _isTou,
            ),
            _note('สิทธิ์ไฟฟรีไม่เกิน 50 หน่วยของผู้ถือบัตรสวัสดิการแห่งรัฐ แอปไม่ได้หักให้'),
          ],
        ),
      ),
      _sources([
        _isBangkok ? 'อัตราไฟฟ้า: กกพ. erc.or.th/th/tariff/1288' : 'อัตราไฟฟ้า: กฟภ. ประกาศอัตราค่าไฟฟ้า (pea.co.th)',
        'ค่า Ft: กกพ. erc.or.th (ประกาศทุก 4 เดือน)',
      ]),
    ];
  }

  // 1 ประเภทอัตรา — ไฮไลต์ประเภทที่แอปใช้คิดให้ผู้ใช้อยู่
  Widget _tariffOption({required String code, required String title, required String detail, required bool inUse}) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.v8),
      padding: const EdgeInsets.all(AppSpacing.v12),
      decoration: BoxDecoration(
        color: inUse ? _accent.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: inUse ? _accent : Colors.grey.shade200, width: inUse ? 1.4 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(code,
                style: TextStyle(
                    fontSize: AppTypography.s13,
                    fontWeight: FontWeight.w700,
                    color: inUse ? _accent : Colors.grey.shade700)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: AppTypography.s13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                const SizedBox(height: AppSpacing.v2),
                Text(detail, style: TextStyle(fontSize: AppTypography.s12, height: 1.4, color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (inUse) ...[
            const SizedBox(width: AppSpacing.v6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v6, vertical: AppSpacing.v2),
              decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
              child: const Text('ของคุณ',
                  style: TextStyle(fontSize: AppTypography.s11, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== น้ำ ====================

  List<Widget> _waterContent() {
    final serviceFee = _isBangkok ? TariffTables.waterMwaServiceFee : TariffTables.waterPwaServiceFee;
    final rows = _isBangkok
        ? _tierRows(TariffTables.waterMwa, _rate2)
        : _tierRows(TariffTables.waterPwa, _rate2, groups: {
            0: 'ใช้ไม่เกิน 50 หน่วย',
            4: 'ใช้เกิน 50 หน่วย (หน่วยที่ 51 ขึ้นไป)',
          });

    return [
      _summaryCard(
        icon: Icons.water_drop_rounded,
        provider: _isBangkok ? 'การประปานครหลวง (MWA)' : 'การประปาส่วนภูมิภาค (PWA)',
        plan: _isBangkok ? 'ประเภทที่อยู่อาศัย' : 'ประเภทที่อยู่อาศัย · ตารางหมายเลข 3',
        facts: [
          (label: 'ค่าบริการ', value: _rate2(serviceFee), unit: 'บาท/เดือน'),
          if (_isBangkok) (label: 'ค่าน้ำดิบ', value: _rate2(TariffTables.waterMwaRawWaterFee), unit: 'บาท/หน่วย'),
          (label: 'ภาษีมูลค่าเพิ่ม', value: '7%', unit: 'ของยอดรวม'),
        ],
      ),
      const SizedBox(height: AppSpacing.v12),
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.v16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle(
              'ตารางอัตราค่าน้ำ',
              subtitle: 'คิดแบบขั้นบันไดเหมือนค่าไฟ ยิ่งใช้มาก หน่วยท้ายๆ ยิ่งแพง',
              infoTitle: 'อัตราขั้นบันไดคืออะไร',
              infoMessage: _isBangkok
                  ? 'หน่วยที่ใช้แต่ละช่วงคิดราคาของช่วงนั้น เช่น ใช้ 35 หน่วย: 30 หน่วยแรกคิดราคาขั้นที่ 1 '
                      'และอีก 5 หน่วยคิดราคาขั้นที่ 2 ไม่ได้คิดราคาเดียวทั้งบิล'
                  : 'ถ้าใช้ไม่เกิน 50 หน่วย คิดราคาตามช่วงในกลุ่มแรก ถ้าใช้เกิน 50 หน่วย หน่วยที่ 51 ขึ้นไป '
                      'คิดราคาตามกลุ่มที่สองแทน\n\n'
                      'ตารางหมายเลข 3 ใช้กับสาขาส่วนใหญ่ทั่วประเทศ บางสาขา เช่น ชลบุรี พัทยา ระยอง ปทุมธานี '
                      'ภูเก็ต เกาะสมุย ใช้ตารางอื่นที่หน่วยเกิน 50 แพงกว่านี้',
            ),
            const SizedBox(height: AppSpacing.v12),
            _rateTable(rows),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.v12),
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.v16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle('บิลค่าน้ำคิดอย่างไร', subtitle: 'ลำดับเดียวกับที่แอปใช้ประมาณยอดให้คุณ'),
            const SizedBox(height: AppSpacing.v14),
            _steps([
              (title: 'ค่าน้ำตามขั้นบันได', detail: 'หน่วยที่ใช้ในแต่ละขั้น × อัตราของขั้นนั้น', extra: null),
              (
                title: 'บวกค่าบริการรายเดือน',
                detail: '${_rate2(serviceFee)} บาท สำหรับมาตรวัดขนาด ½ นิ้วของบ้านทั่วไป',
                extra: null
              ),
              if (_isBangkok)
                (
                  title: 'บวกค่าน้ำดิบ',
                  detail: 'หน่วยที่ใช้ทั้งหมด × ${_rate2(TariffTables.waterMwaRawWaterFee)} บาท',
                  extra: null
                ),
              (
                title: 'บวกภาษีมูลค่าเพิ่ม 7%',
                detail: 'คิดจากยอดรวมข้อ 1-${_isBangkok ? 3 : 2} ได้เป็นยอดที่ต้องจ่าย',
                extra: null
              ),
            ]),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.v12),
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.v16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle('ข้อควรรู้'),
            _note('ค่าบริการขึ้นกับขนาดมาตรวัดน้ำ ถ้าบ้านคุณใช้มาตรใหญ่กว่า ½ นิ้ว ค่าบริการจริงจะสูงกว่าที่แอปคิด'),
            _note('ประเภทที่อยู่อาศัยไม่มีค่าน้ำขั้นต่ำ ใช้น้อยก็จ่ายตามจริง'
                '${_isBangkok ? ' (กปน. ยกเลิกค่าน้ำขั้นต่ำตั้งแต่ เม.ย. 2558)' : ''}'),
          ],
        ),
      ),
      _sources([
        _isBangkok
            ? 'อัตราค่าน้ำ: กปน. mwa.co.th (อัตราค่าน้ำและบริการ)'
            : 'อัตราค่าน้ำ: กปภ. pwa.co.th (อัตราค่าน้ำประปาส่วนภูมิภาค)',
      ]),
    ];
  }
}
