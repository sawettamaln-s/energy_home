part of 'analysis_screen.dart';

// ==================== Tab ไฟฟ้า / น้ำ ====================
// เรียงตามสิ่งที่ผู้ใช้อยากรู้:
//   1) การ์ดคาดการณ์ — รอบนี้จะจบที่เท่าไร และบิลรอบถัดไปน่าจะเท่าไร
//   2) กราฟประวัติและคาดการณ์ 3 เดือนข้างหน้า
//   3) การ์ดเปรียบเทียบบิลล่าสุด (เดือนก่อน / ปีก่อน / เฉลี่ย 6 เดือน)
//   4) ข้อสังเกต ไม่เกิน 3 ข้อ และไม่ซ้ำกับการ์ดเปรียบเทียบ
class _UtilityTab extends StatelessWidget {
  final List<BillModel> bills;
  final AnalysisService analysisService;
  final double Function(BillModel) selector; // ค่าใช้จ่าย (บาท)
  // หน่วยที่ใช้จริง (electricityUsed/waterUsed) — ใช้กับกราฟเทรนด์โหมด
  // หน่วยที่ใช้ แยกจาก selector (ค่าใช้จ่าย) เพราะเป็นคนละมิติกัน บิลบาง
  // เดือนอาจมีค่าใช้จ่ายแต่ไม่มีหน่วย (เช่น บิลที่มาจากการตั้งเลขมิเตอร์
  // ต้นรอบครั้งแรกสุดของบัญชี ที่คำนวณ delta หน่วยที่ใช้ไม่ได้จริงๆ)
  final double Function(BillModel) usedSelector;
  final String unitLabel; // หน่วยที่ใช้ เช่น 'หน่วย'
  final String title; // หัวข้อยาว เช่น 'ค่าไฟฟ้า' ใช้ในกราฟเทรนด์
  final String label; // หัวข้อสั้น เช่น 'ค่าไฟ' ใช้ในข้อความ insight
  // สีประจำยูทิลิตี้ (น้ำตาล-ส้ม = ไฟฟ้า, ฟ้า = น้ำ) ให้ตรงกับโทนสีที่
  // dashboard ใช้ (DashboardStyles.electricityBorder/waterBorder)
  final Color accentColor;
  // สีกราฟแท่งเทรนด์ แยกโหมด "ค่าใช้จ่าย"/"หน่วย" (+ Off-Peak สำหรับ TOU)
  final Color costColor;
  final Color unitColor;
  final Color? touOffPeakColor;
  final CurrentCycleForecast? currentCycle;
  // TOU เท่านั้น (แท็บไฟฟ้า) — กราฟเทรนด์ฝั่ง "หน่วยที่ใช้" โชว์เป็นแท่งซ้อน
  // On-Peak/Off-Peak แท็บน้ำไม่ส่งมา (default false/null)
  final bool isTou;
  final double Function(BillModel)? peakUsedSelector;
  final double Function(BillModel)? offPeakUsedSelector;

  // area/meterType ของ user คนนี้ ('bangkok'/'province', 'normal'/'tou') —
  // ส่งต่อให้ analysisService เลือก seasonal curve ให้ตรงเคส ถ้าเป็น null
  // analysisService จะ fallback ไปใช้ linear regression เอง
  final String? area;
  final String? meterType;
  // true เฉพาะแท็บน้ำ — ใช้เลือก SeasonalCurves.water แทน .elec
  final bool isWater;

  // เรียกตอนกดปุ่ม "ดูอุปกรณ์ที่ใช้ไฟมากสุด" ในข้อสังเกต — ให้ AnalysisScreen
  // สลับไปแท็บอุปกรณ์ (index 2)
  final VoidCallback? onViewAppliances;

  // หน้าอุปกรณ์เก็บเฉพาะข้อมูลการใช้ไฟฟ้า — แท็บน้ำปิดปุ่มนี้
  final bool trackAppliances;

  static final _fmt = NumberFormat('#,##0.00');
  static final _fmtUnit = NumberFormat('#,##0.#');
  static final _fmtBaht = NumberFormat('#,##0');

  const _UtilityTab({
    required this.bills,
    required this.analysisService,
    required this.selector,
    required this.usedSelector,
    required this.unitLabel,
    required this.title,
    required this.label,
    required this.accentColor,
    required this.costColor,
    required this.unitColor,
    this.touOffPeakColor,
    required this.currentCycle,
    this.onViewAppliances,
    this.trackAppliances = true,
    this.isTou = false,
    this.peakUsedSelector,
    this.offPeakUsedSelector,
    this.area,
    this.meterType,
    this.isWater = false,
  });

  @override
  Widget build(BuildContext context) {
    final mom = analysisService.compareMoM(bills, selector: selector);
    final yoy = analysisService.compareYoY(bills, selector: selector);
    final avg6 = analysisService.compareToAverage(bills, selector: selector);
    final nextBillMonth = _nextBillMonth;
    final forecast = analysisService.forecastNextMonth(
      bills,
      selector: selector,
      area: area,
      meterType: meterType,
      isWater: isWater,
      targetMonth: nextBillMonth,
    );
    final multiMonthForecast = _withCurrentCycle(
      analysisService.forecastNextMonths(
        bills,
        selector: selector,
        months: 3,
        area: area,
        meterType: meterType,
        isWater: isWater,
      ),
      (c) => c.forecastCost,
    );
    // คาดการณ์ฝั่ง "หน่วยที่ใช้" (กราฟเทรนด์สลับโหมดได้) — เส้นฤดูกาลสร้างจาก
    // ยอดหน่วยอยู่แล้ว (tool/seasonal_curves) ยอดรวมทั้งเดือนไม่แยก On/Off-Peak
    final multiMonthUsedForecast = _withCurrentCycle(
      analysisService.forecastNextMonths(
        bills,
        selector: usedSelector,
        months: 3,
        area: area,
        meterType: meterType,
        isWater: isWater,
      ),
      (c) => c.forecastUnits,
    );

    // การ์ดเปรียบเทียบแสดงผลเทียบเดือนก่อน/ปีก่อนอยู่แล้ว จึงไม่สร้างข้อสังเกต
    // ที่พูดเรื่องเดียวกันซ้ำ และแสดงแค่ 3 ข้อแรกให้อ่านจบได้เร็ว
    final insights = analysisService
        .generateUtilityInsights(
          label: label,
          bills: bills,
          selector: selector,
          mom: mom,
          yoy: yoy,
          currentCycle: currentCycle,
          trackAppliances: trackAppliances,
          includeComparisons: false,
        )
        .take(3)
        .toList();

    // ข้อมูลน้อยกว่า 3 เดือน = ค่าคาดการณ์ยังไม่น่าเชื่อถือ ไม่ว่าจะใช้วิธีไหน:
    // - รู้ area+meterType → seasonal curve หา "ระดับการใช้ปัจจุบัน" จากบิล
    //   ล่าสุดไม่เกิน 3 เดือน ถ้ามีแค่ 1-2 เดือน ระดับนี้จะแกว่งตามเดือนที่มี
    // - ไม่รู้ → เส้นแนวโน้ม (linear regression) บนจุดข้อมูล 1-2 จุดก็แค่ทาบ
    //   เส้นผ่านจุดที่มีเท่านั้น
    final forecastLowConfidence = bills.length < 3;

    // true เมื่อรู้ area+meterType ของ user คนนี้แล้ว (เงื่อนไขเดียวกับ
    // _resolveCurve ใน analysis_service.dart)
    final usesSeasonalCurve = area != null && meterType != null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.v16),
      children: [
        FadeSlideIn(
          child: _forecastCard(
            context,
            forecast,
            targetMonth: nextBillMonth,
            lowConfidence: forecastLowConfidence,
            usesSeasonalCurve: usesSeasonalCurve,
          ),
        ),
        const SizedBox(height: AppSpacing.v16),
        FadeSlideIn(
          delay: const Duration(milliseconds: 80),
          child: _TrendChartCard(
            bills: bills,
            title: title,
            unitLabel: unitLabel,
            costSelector: selector,
            usedSelector: usedSelector,
            accentColor: accentColor,
            costColor: costColor,
            unitColor: unitColor,
            touOffPeakColor: touOffPeakColor,
            isTou: isTou,
            peakUsedSelector: peakUsedSelector,
            offPeakUsedSelector: offPeakUsedSelector,
            costForecast: multiMonthForecast,
            usedForecast: multiMonthUsedForecast,
            forecastLowConfidence: forecastLowConfidence,
            usesSeasonalCurve: usesSeasonalCurve,
          ),
        ),
        if (bills.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.v16),
          FadeSlideIn(
            delay: const Duration(milliseconds: 160),
            child: _comparisonCard(context, mom: mom, yoy: yoy, avg6: avg6),
          ),
        ],
        if (insights.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.v16),
          FadeSlideIn(
            delay: const Duration(milliseconds: 240),
            child: _InsightsCard(
              insights: insights,
              onViewAppliances: onViewAppliances,
            ),
          ),
        ],
      ],
    );
  }

  // เดือนของบิลที่ส่วน "รอบถัดไป" ทาย = บิลถัดจากรอบที่กำลังใช้อยู่ ถ้ามีบิล
  // ที่ใหม่กว่านั้นอยู่แล้วใช้เดือนถัดจากบิลล่าสุด — ไม่มีบิลเลยคืน null
  DateTime? get _nextBillMonth {
    if (bills.isEmpty) return null;
    final afterLastBill = DateTime(bills.last.year, bills.last.month + 1, 1);
    final c = currentCycle;
    if (c == null) return afterLastBill;
    final afterCycle = DateTime(c.billMonth.year, c.billMonth.month + 1, 1);
    return afterCycle.isAfter(afterLastBill) ? afterCycle : afterLastBill;
  }

  // แท่งคาดการณ์ในกราฟเทรนด์เริ่มจากเดือนถัดจากบิลล่าสุด — แท่งที่ตรงกับบิล
  // ของรอบที่กำลังใช้อยู่ใช้ตัวเลขเดียวกับส่วน "รอบนี้" ของการ์ดคาดการณ์ (อัตรา
  // ต่อวันจากบันทึกจริง) แทนค่าจากรูปแบบฤดูกาล ตัวเลขของบิลใบเดียวกันจึงตรงกัน
  // ทั้งหน้า (รอบนี้ยังไม่มีบันทึกใช้ค่าจากรูปแบบฤดูกาลตามเดิม)
  List<double> _withCurrentCycle(
    List<double> forecasts,
    double Function(CurrentCycleForecast) pick,
  ) {
    final c = currentCycle;
    if (c == null || !c.hasData || bills.isEmpty) return forecasts;
    return [
      for (var i = 0; i < forecasts.length; i++)
        DateTime(bills.last.year, bills.last.month + i + 1, 1) == c.billMonth
            ? pick(c)
            : forecasts[i],
    ];
  }

  String _monthYear(DateTime d) => '${thaiMonthsShort[d.month - 1]} ${(d.year + 543) % 100}';

  // ===================================================================
  // การ์ดคาดการณ์ — รอบนี้ (จากบันทึกมิเตอร์จริง) + รอบถัดไป (จากบิลย้อนหลัง
  // และรูปแบบฤดูกาล) ในการ์ดเดียว ส่วนไหนยังไม่มีข้อมูลจะบอกวิธีให้มีข้อมูล
  // ===================================================================
  Widget _forecastCard(
    BuildContext context,
    double forecast, {
    required DateTime? targetMonth,
    required bool lowConfidence,
    required bool usesSeasonalCurve,
  }) {
    final c = currentCycle;
    final hasCurrent = c != null && c.hasData;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: Icons.insights_rounded, color: accentColor, size: 34),
              const SizedBox(width: AppSpacing.v10),
              Expanded(
                child: Text('คาดการณ์$title',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: AppTypography.s15, color: AppColors.textDark)),
              ),
              _InfoButton(
                onTap: () => showInfoDialog(
                  context,
                  title: 'ตัวเลขคาดการณ์คำนวณอย่างไร?',
                  message: _forecastInfoText(usesSeasonalCurve),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v14),
          _forecastBlock(
            title: 'บิลรอบนี้',
            month: c?.billMonth,
            trailing: hasCurrent ? 'เหลืออีก ${c.remainingDays} วัน' : null,
            children: hasCurrent
                ? [
                    _estimateLine(c.forecastCost),
                    const SizedBox(height: AppSpacing.v4),
                    Text(
                      'ถึงวันนี้ใช้ไปแล้ว ${_fmt.format(c.currentCost)} บาท · '
                      'ทั้งรอบน่าจะใช้ประมาณ ${_fmtUnit.format(c.forecastUnits)} $unitLabel',
                      style: TextStyle(fontSize: AppTypography.s12, height: 1.45, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: AppSpacing.v10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.v4),
                      child: LinearProgressIndicator(
                        value: c.progress,
                        minHeight: 6,
                        backgroundColor: accentColor.withValues(alpha: 0.14),
                        valueColor: AlwaysStoppedAnimation(accentColor),
                      ),
                    ),
                  ]
                : [_emptyHint('บันทึกมิเตอร์ในรอบนี้อย่างน้อย 1 ครั้ง เพื่อดูว่า$titleรอบนี้จะจบที่เท่าไรค่ะ')],
          ),
          const SizedBox(height: AppSpacing.v10),
          _forecastBlock(
            title: 'บิลรอบถัดไป',
            month: targetMonth,
            children: targetMonth != null
                ? _nextCycleDetails(
                    forecast,
                    targetMonth: targetMonth,
                    lowConfidence: lowConfidence,
                    usesSeasonalCurve: usesSeasonalCurve,
                  )
                : [_emptyHint('เพิ่มบิลย้อนหลังที่หน้าตั้งค่า เพื่อให้ระบบคาดการณ์บิลรอบถัดไปได้ค่ะ')],
          ),
        ],
      ),
    );
  }

  // กล่องของยอดคาดการณ์ 1 ยอด — ป้ายบอกว่าเป็นบิลรอบไหนอยู่บนสุด (อ่านก่อน
  // ตัวเลข) ตามด้วยรายละเอียด แยกรอบนี้/รอบถัดไปเป็นคนละกล่องให้เห็นว่าเป็นคนละยอด
  Widget _forecastBlock({
    required String title,
    required DateTime? month,
    String? trailing,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: BoxDecoration(
        color: DashboardStyles.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  month != null ? '$title · ${_monthYear(month)}' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600, color: AppColors.textDark),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.v8),
                Flexible(
                  child: Text(trailing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.v6),
          ...children,
        ],
      ),
    );
  }

  // ยอดคาดการณ์ "ประมาณ 2,065 บาท" — บาทเต็มไม่มีทศนิยม (เป็นค่าประมาณ) แต่ไม่ปัด
  // หลักสิบ/ร้อยแยกทีละยอด ค่าไฟ + ค่าน้ำรอบนี้จึงบวกกันได้เท่ากับยอดคาดการณ์
  // สิ้นรอบที่หน้าหลัก (หน้าหลักบวกรายจ่ายประจำแล้วปัดยอดรวมครั้งเดียว)
  Widget _estimateLine(double value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.v4),
          child: Text('ประมาณ', style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade700)),
        ),
        const SizedBox(width: AppSpacing.v6),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedAmount(
              value: value.roundToDouble(),
              pattern: '#,##0',
              style: TextStyle(fontSize: AppTypography.s24, fontWeight: FontWeight.w700, color: _darkAccent),
            ),
          ),
        ),
      ],
    );
  }

  // สีเข้มขึ้นของสีประจำยูทิลิตี้ ใช้กับตัวเลขยอดคาดการณ์
  Color get _darkAccent => Color.alphaBlend(Colors.black.withValues(alpha: 0.25), accentColor);

  List<Widget> _nextCycleDetails(
    double forecast, {
    required DateTime targetMonth,
    required bool lowConfidence,
    required bool usesSeasonalCurve,
  }) {
    final lastBill = bills.last;
    final lastValue = selector(lastBill);
    final comparison =
        lastValue > 0 ? ComparisonResult(currentValue: forecast, previousValue: lastValue) : null;
    // บิลล่าสุดที่ใช้เทียบ "ผิดปกติ" จากค่าเฉลี่ย 6 เดือนมากไหม — ถ้าใช่ % ที่
    // เทียบจะดูเกินจริง ต้องบอกผู้ใช้ไว้ ไม่ให้เข้าใจว่าคาดการณ์พลาด
    final avg6 = bills.length >= 3 ? analysisService.compareToAverage(bills, selector: selector) : null;
    final lastBillIsAnomalousBase =
        avg6 != null && avg6.percentChange != null && avg6.percentChange!.abs() >= _anomalyThresholdPercent;
    final seasonalFactor = usesSeasonalCurve
        ? analysisService.seasonalFactorForMonth(
            month: targetMonth.month,
            area: area,
            meterType: meterType,
            isWater: isWater,
          )
        : null;
    final (seasonIcon, seasonColor) = _seasonVisual(_seasonFor(targetMonth.month));
    final lastName = _monthYear(DateTime(lastBill.year, lastBill.month));

    return [
      _estimateLine(forecast),
      if (comparison != null) ...[
        const SizedBox(height: AppSpacing.v6),
        _deltaLine(
          comparison,
          _isClose(comparison)
              ? 'ใกล้เคียงบิล $lastName'
              : '${comparison.isIncrease ? 'สูงกว่า' : 'ต่ำกว่า'}บิล $lastName '
                  '${comparison.percentChange != null ? '${comparison.percentChange!.abs().toStringAsFixed(0)}% ' : ''}'
                  '(${comparison.isIncrease ? '+' : '−'}${_fmtBaht.format(comparison.diff.abs())} บาท)',
        ),
      ],
      if (seasonalFactor != null) ...[
        const SizedBox(height: AppSpacing.v8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.v1),
              child: Icon(seasonIcon, size: 15, color: seasonColor),
            ),
            const SizedBox(width: AppSpacing.v6),
            Expanded(
              child: Text(
                _seasonReasonText(targetMonth.month, seasonalFactor),
                style: TextStyle(fontSize: AppTypography.s12, height: 1.45, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ],
      if (lastBillIsAnomalousBase || lowConfidence) ...[
        const SizedBox(height: AppSpacing.v10),
        _warningNote([
          if (lowConfidence) 'ประมาณการเบื้องต้น เพราะมีบิลเพียง ${bills.length} เดือน',
          if (lastBillIsAnomalousBase) 'บิล $lastName ต่างจากค่าเฉลี่ยมาก ตัวเลขที่เทียบจึงอาจดูต่างเกินจริง',
        ].join(' · ')),
      ],
    ];
  }

  String _forecastInfoText(bool usesSeasonalCurve) {
    const current = 'รอบนี้\n'
        'หาหน่วยที่ใช้เฉลี่ยต่อวันตั้งแต่ต้นรอบถึงวันที่บันทึกมิเตอร์ล่าสุด '
        'แล้วประมาณหน่วยทั้งรอบจนถึงวันตัดรอบบิล จากนั้นคิดเงินด้วยอัตราจริง '
        '(อัตราขั้นบันได ค่าบริการ และ VAT) หากใช้งานไม่สม่ำเสมอมาก ตัวเลขอาจคลาดเคลื่อนได้บ้าง';
    final next = usesSeasonalCurve
        ? 'รอบถัดไป\n'
            'เอาค่าเฉลี่ย$labelไม่กี่เดือนล่าสุดของคุณ มาปรับด้วยรูปแบบฤดูกาล '
            '(เช่น เดือนร้อนมักใช้ไฟมากกว่าเดือนหนาว) รูปแบบฤดูกาลคำนวณจากสถิติการใช้'
            'ไฟฟ้า/น้ำประปาจริงรายเดือนย้อนหลังหลายปี (ข้อมูลเปิดของ สนพ., กปน. และ กปภ.) '
            'แยกตามพื้นที่ของคุณ'
        : 'รอบถัดไป\n'
            'ประมาณแนวโน้มจากยอด$labelย้อนหลังทั้งหมดที่บันทึกไว้ แล้วลากเส้นแนวโน้มต่อไป '
            'ยิ่งมีข้อมูลสะสมหลายเดือน ตัวเลขยิ่งแม่นยำขึ้น';
    return '$current\n\n$next';
  }

  Widget _emptyHint(String text) {
    return Text(text, style: TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: Colors.grey.shade600));
  }

  // บรรทัดผลต่างพร้อมลูกศร — สูงขึ้นสีแดง ลดลงสีเขียว ใกล้เคียงสีเทา
  // ต่างไม่ถึง 5% ถือว่าใกล้เคียง (เกณฑ์เดียวกับชิปเทียบบิลก่อนที่หน้าหลัก)
  static bool _isClose(ComparisonResult r) =>
      r.isUnchanged || (r.percentChange != null && r.percentChange!.abs() < 5);

  Widget _deltaLine(ComparisonResult r, String text) {
    final close = _isClose(r);
    final tone = close ? Colors.grey.shade600 : _toneOf(r);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.v1),
          child: Icon(close ? Icons.trending_flat_rounded : _trendIconOf(r), size: 16, color: tone),
        ),
        const SizedBox(width: AppSpacing.v6),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600, color: tone)),
        ),
      ],
    );
  }

  Widget _warningNote(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v10, vertical: AppSpacing.v8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.v1),
            child: Icon(Icons.info_outline, size: 14, color: AppColors.warningIcon),
          ),
          const SizedBox(width: AppSpacing.v6),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: AppTypography.s11_5, height: 1.4, color: AppColors.warningText)),
          ),
        ],
      ),
    );
  }

  // ===================================================================
  // การ์ดเปรียบเทียบบิลล่าสุด — 3 แถว: เดือนก่อน / ปีก่อน / เฉลี่ย 6 เดือน
  // แต่ละแถวบอกยอดที่ใช้เทียบ และ % ที่เปลี่ยน (ข้อมูลไม่พอบอกเงื่อนไขแทน)
  // ===================================================================
  static const double _anomalyThresholdPercent = 70;

  Widget _comparisonCard(
    BuildContext context, {
    required ComparisonResult? mom,
    required ComparisonResult? yoy,
    required ComparisonResult? avg6,
  }) {
    final last = bills.last;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.compare_arrows_rounded, color: AppColors.primaryGreen, size: 34),
              const SizedBox(width: AppSpacing.v10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('เทียบบิลล่าสุด',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: AppTypography.s15, color: AppColors.textDark)),
                    Text(
                      'บิล ${_monthYear(DateTime(last.year, last.month))} · ${_fmt.format(selector(last))} บาท',
                      style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              _InfoButton(
                onTap: () => showInfoDialog(
                  context,
                  title: 'เทียบอย่างไร?',
                  message: 'เทียบยอด$labelของบิลล่าสุดกับ 3 อย่าง\n\n'
                      'เดือนก่อน: บิลเดือนก่อนหน้าเดือนเดียว ดูการเปลี่ยนแปลงระยะสั้น\n\n'
                      'ปีก่อน: บิลเดือนเดียวกันของปีที่แล้ว ดูผลของฤดูกาล '
                      'เช่น หน้าร้อนมักใช้ไฟมากกว่าหน้าฝน\n\n'
                      'เฉลี่ย 6 เดือน: ค่าเฉลี่ยของบิล 6 เดือนก่อนหน้า (นับเฉพาะเดือนที่มีบิล) '
                      'ภาพนิ่งกว่าเทียบเดือนเดียว\n\n'
                      'คำนวณ % จาก (ยอดบิลล่าสุด − ยอดที่ใช้เทียบ) ÷ ยอดที่ใช้เทียบ × 100 '
                      'ถ้ายอดที่ใช้เทียบเป็น 0 บาท จะแสดงเป็นส่วนต่างบาทแทน',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v8),
          _comparisonRow('เดือนก่อน', mom,
              emptyHint: 'ต้องมีบิลเดือนก่อนหน้า'),
          const Divider(),
          _comparisonRow('ปีก่อน', yoy,
              emptyHint: 'ยังไม่มีบิลเดือนเดียวกันของปีก่อน'),
          const Divider(),
          _comparisonRow('เฉลี่ย 6 เดือน', avg6,
              emptyHint: 'ต้องมีบิลอย่างน้อย 3 เดือน (ตอนนี้มี ${bills.length} เดือน)'),
        ],
      ),
    );
  }

  Widget _comparisonRow(String label, ComparisonResult? r, {required String emptyHint}) {
    const labelStyle =
        TextStyle(fontSize: AppTypography.s13, fontWeight: FontWeight.w500, color: AppColors.textDark);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.v10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: AppSpacing.v2),
                Text(
                  r == null ? emptyHint : '${_fmt.format(r.previousValue)} บาท',
                  style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (r != null) ...[
            const SizedBox(width: AppSpacing.v8),
            _changeChip(r),
          ],
        ],
      ),
    );
  }

  Widget _changeChip(ComparisonResult r) {
    final tone = _toneOf(r);
    final text = r.isUnchanged
        ? 'เท่าเดิม'
        : r.percentChange == null
            ? '${r.isIncrease ? '+' : '−'}${_fmt.format(r.diff.abs())} บาท'
            : '${r.isIncrease ? '+' : '−'}${r.percentChange!.abs().toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v10, vertical: AppSpacing.v5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.v20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_trendIconOf(r), size: 15, color: tone),
          const SizedBox(width: AppSpacing.v4),
          Text(text,
              style: TextStyle(
                  fontSize: AppTypography.s13,
                  fontWeight: FontWeight.w700,
                  color: tone,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  // สีตามความหมาย: ลด = เขียว, เพิ่ม = แดง, เปลี่ยนมากผิดปกติ = ส้ม, เท่ากัน = เทา
  Color _toneOf(ComparisonResult r) {
    if (r.isUnchanged) return Colors.grey.shade600;
    if (r.percentChange != null && r.percentChange!.abs() >= _anomalyThresholdPercent) {
      return AppColors.warningIcon;
    }
    return r.isIncrease ? DashboardStyles.spikeUp : DashboardStyles.spikeDown;
  }

  IconData _trendIconOf(ComparisonResult r) {
    if (r.isUnchanged) return Icons.trending_flat_rounded;
    return r.isIncrease ? Icons.trending_up_rounded : Icons.trending_down_rounded;
  }

  // ===================================================================
  // ฤดูกาลของเดือนที่คาดการณ์
  // ===================================================================
  String _seasonName(int month) {
    if (month >= 3 && month <= 5) return 'ช่วงฤดูร้อน';
    if (month >= 6 && month <= 10) return 'ช่วงฤดูฝน';
    return 'ช่วงฤดูหนาว';
  }

  _Season _seasonFor(int month) {
    if (month >= 3 && month <= 5) return _Season.summer;
    if (month >= 6 && month <= 10) return _Season.rainy;
    return _Season.cool;
  }

  (IconData, Color) _seasonVisual(_Season season) {
    switch (season) {
      case _Season.summer:
        return (Icons.wb_sunny_rounded, AppColors.seasonSummer);
      case _Season.rainy:
        return (Icons.umbrella_rounded, AppColors.seasonRainy);
      case _Season.cool:
        return (Icons.ac_unit_rounded, AppColors.seasonCool);
    }
  }

  String _seasonReasonText(int month, double factor) {
    final monthName = thaiMonthsShort[month - 1];
    final season = _seasonName(month);
    final pct = ((factor - 1).abs() * 100).round();
    if (factor > 1.05) {
      return '$monthName อยู่$season มักใช้$labelมากกว่าค่าเฉลี่ยทั้งปีประมาณ $pct%';
    }
    if (factor < 0.95) {
      return '$monthName อยู่$season มักใช้$labelน้อยกว่าค่าเฉลี่ยทั้งปีประมาณ $pct%';
    }
    return '$monthName อยู่$season มักใช้$labelใกล้เคียงค่าเฉลี่ยทั้งปี';
  }
}

// ฤดูกาลของการ์ดคาดการณ์: ร้อน = พระอาทิตย์, ฝน = ร่ม, หนาว = เกล็ดหิมะ
enum _Season { summer, rainy, cool }

// ปุ่ม ⓘ มุมขวาของหัวการ์ด — พื้นที่กดกว้างกว่าตัวไอคอน
class _InfoButton extends StatelessWidget {
  final VoidCallback onTap;

  const _InfoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'คำอธิบาย',
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.info_outline, size: 20, color: Colors.grey.shade500),
    );
  }
}

// =====================================================================
// การ์ดข้อสังเกต — ใช้ร่วมกันทั้งแท็บไฟฟ้า/น้ำ และแท็บอุปกรณ์
// =====================================================================
class _InsightsCard extends StatelessWidget {
  final List<AnalysisInsight> insights;
  final VoidCallback? onViewAppliances;

  const _InsightsCard({required this.insights, this.onViewAppliances});

  static IconData _iconOf(InsightLevel level) => switch (level) {
        InsightLevel.good => Icons.check_circle_outline_rounded,
        InsightLevel.warning => Icons.warning_amber_rounded,
        InsightLevel.neutral => Icons.info_outline,
      };

  static Color _colorOf(InsightLevel level) => switch (level) {
        InsightLevel.good => AppColors.primaryGreen,
        InsightLevel.warning => AppColors.warningIcon,
        InsightLevel.neutral => Colors.grey.shade600,
      };

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              IconBadge(icon: Icons.lightbulb_outline_rounded, color: AppColors.primaryGreen, size: 34),
              SizedBox(width: AppSpacing.v10),
              Text('ข้อสังเกต',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: AppTypography.s15, color: AppColors.textDark)),
            ],
          ),
          const SizedBox(height: AppSpacing.v12),
          for (final (i, insight) in insights.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.v12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.v1),
                  child: Icon(_iconOf(insight.level), size: 18, color: _colorOf(insight.level)),
                ),
                const SizedBox(width: AppSpacing.v10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(insight.text,
                          style: const TextStyle(
                              fontSize: AppTypography.s13, height: 1.45, color: AppColors.textDark)),
                      if (insight.showApplianceCta && onViewAppliances != null)
                        TextButton.icon(
                          onPressed: onViewAppliances,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 34),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: AppTypography.s12_5,
                                fontWeight: FontWeight.w600),
                          ),
                          iconAlignment: IconAlignment.end,
                          icon: const Icon(Icons.chevron_right_rounded, size: 18),
                          label: const Text('ดูอุปกรณ์ที่ใช้ไฟมากสุด'),
                        ),
                    ],
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
