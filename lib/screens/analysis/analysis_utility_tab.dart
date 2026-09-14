part of 'analysis_screen.dart';

// ==================== Tab ไฟฟ้า / น้ำ ====================
class _UtilityTab extends StatelessWidget {
  final List<BillModel> bills;
  final AnalysisService analysisService;
  final double Function(BillModel) selector; // ค่าใช้จ่าย (บาท)
  // หน่วยที่ใช้จริง (electricityUsed/waterUsed) — เพิ่มใหม่สำหรับกราฟเทรนด์
  // หน่วยที่ใช้ แยกจาก selector (ค่าใช้จ่าย) เพราะเป็นคนละมิติกัน บิลบาง
  // เดือนอาจมีค่าใช้จ่ายแต่ไม่มีหน่วย (เช่น บิลที่มาจากการตั้งเลขมิเตอร์
  // ต้นรอบครั้งแรกสุดของบัญชี ที่คำนวณ delta หน่วยที่ใช้ไม่ได้จริงๆ)
  final double Function(BillModel) usedSelector;
  final String unitLabel; // หน่วยที่ใช้ เช่น 'หน่วย'
  final String title; // หัวข้อยาว เช่น 'ค่าไฟฟ้า' ใช้ในกราฟเทรนด์
  final String label; // หัวข้อสั้น เช่น 'ค่าไฟ' ใช้ในข้อความ insight
  // สีประจำยูทิลิตี้ (ส้ม = ไฟฟ้า, ฟ้าอมเขียว = น้ำ) ใช้กับกราฟเทรนด์และ
  // ปุ่มสลับมุมมอง (ค่าใช้จ่าย/หน่วย) ให้ตรงกับโทนสีที่ dashboard ใช้อยู่
  // แล้ว (DashboardStyles.electricityBorder/waterBorder) แทนที่จะใช้สีเขียว
  // เดียวกันหมดทั้ง 2 แท็บเหมือนเดิม แยกไม่ออกว่ากำลังดูแท็บไหนอยู่จากกราฟ
  final Color accentColor;
  // พาเลตสีจริงของกราฟแท่งเทรนด์ ต่อโหมด "ค่าใช้จ่าย"/"หน่วย" — เลือกเฉด
  // เฉพาะของแต่ละยูทิลิตี้ (ไฟฟ้า = แดง/เหลือง, น้ำ = น้ำเงิน) ตรงตาม swatch
  final Color costColor;
  final Color unitColor;
  final Color? touOffPeakColor;
  final CurrentCycleForecast? currentCycle;
  // TOU เท่านั้น (แท็บไฟฟ้า) — ใช้ให้กราฟเทรนด์ฝั่ง "หน่วยที่ใช้" โชว์เป็น
  // แท่งซ้อน On-Peak/Off-Peak แทนแท่งทึบสีเดียว แท็บน้ำไม่ส่งมาเลย (default
  // false/null) จึงยังเป็นแท่งเดียวเหมือนเดิมทุกอย่าง
  final bool isTou;
  final double Function(BillModel)? peakUsedSelector;
  final double Function(BillModel)? offPeakUsedSelector;

  // area/meterType ของ user คนนี้ ('bangkok'/'province', 'normal'/'tou') —
  // ส่งต่อให้ analysisService เลือก seasonal curve ให้ตรงเคส ถ้าเป็น null
  // (เช่น ยังโหลด user ไม่เสร็จ) analysisService จะ fallback ไปใช้ linear
  // regression เดิมเองโดยอัตโนมัติ (ดู _resolveCurve ใน analysis_service.dart)
  final String? area;
  final String? meterType;
  // true เฉพาะแท็บน้ำ — ใช้เลือก SeasonalCurves.water แทน .elec
  final bool isWater;

  // เรียกตอนกดปุ่ม "ดูอุปกรณ์" ในการ์ดข้อสังเกต (เดือนที่ใช้สูงสุด) — ให้
  // AnalysisScreen สลับ TabController ไปแท็บอุปกรณ์ (index 2) แทนที่จะบอก
  // ข้อสังเกตเฉยๆ แล้วจบ ผู้ใช้กดต่อไปดูได้เลยว่าเครื่องไหนกินไฟเยอะสุด
  final VoidCallback? onViewAppliances;

  // หน้าอุปกรณ์เก็บเฉพาะข้อมูลการใช้ไฟฟ้า (ไม่มีตารางอุปกรณ์ใช้น้ำ) — ใช้
  // ตัวนี้กันไม่ให้ปุ่ม CTA "ดูอุปกรณ์" โผล่ในแท็บน้ำ ซึ่งกดไปแล้วจะเจอ
  // ข้อมูลที่ไม่เกี่ยวข้องกับสิ่งที่ผู้ใช้กำลังดูอยู่
  final bool trackAppliances;

  static const _green = DashboardStyles.primaryGreen;
  final _fmt = NumberFormat('#,##0.00');
  final _fmtUnit = NumberFormat('#,##0.0');

  _UtilityTab({
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
    final forecast = analysisService.forecastNextMonth(
      bills,
      selector: selector,
      area: area,
      meterType: meterType,
      isWater: isWater,
    );
    final multiMonthForecast = analysisService.forecastNextMonths(
      bills,
      selector: selector,
      months: 3,
      area: area,
      meterType: meterType,
      isWater: isWater,
    );

    final insights = analysisService.generateUtilityInsights(
      label: label,
      bills: bills,
      selector: selector,
      mom: mom,
      yoy: yoy,
      forecastNextMonth: forecast,
      currentCycle: currentCycle,
      trackAppliances: trackAppliances,
    );

    // ข้อมูลน้อยกว่า 3 เดือน = แนวโน้มระยะยาวยังไม่มีความหมายทางสถิติจริงๆ
    // (linear regression บนจุดข้อมูล 1-2 จุด ก็แค่ทาบเส้นผ่านจุดที่มีเท่านั้น)
    // ใช้กำกับความมั่นใจของตัวเลข ไม่ให้ผู้ใช้เข้าใจว่าแม่นยำร้อยเปอร์เซ็นต์
    final forecastLowConfidence = bills.length < 3;

    // true เมื่อรู้ area+meterType ของ user คนนี้แล้ว (เงื่อนไขเดียวกับ
    // _resolveCurve ใน analysis_service.dart) — ใช้ตัดสินว่าจะโชว์ badge
    // "ปรับตามฤดูกาล" และเปลี่ยนข้อความอธิบายในการ์ดคาดการณ์ไหม
    final usesSeasonalCurve = area != null && meterType != null;

    final overviewSummary = _overviewSummary(mom, avg6);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (overviewSummary != null) ...[
          _overviewBanner(overviewSummary),
          const SizedBox(height: 16),
        ],
        if (currentCycle != null && currentCycle!.hasData) ...[
          _currentCycleCard(context),
          const SizedBox(height: 16),
        ],
        _TrendChartCard(
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
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _comparisonCard(
                context,
                'เทียบเดือนก่อน',
                mom,
                previousLabel: 'เดือนก่อน',
                emptyHint:
                    'ต้องมีบิลอย่างน้อย 2 เดือน (ตอนนี้มี ${bills.length} เดือน)',
                infoTitle: 'เทียบเดือนก่อนคืออะไร?',
                infoMessage:
                    'เทียบยอด$labelของเดือนล่าสุดกับเดือนก่อนหน้าเดือนเดียว '
                    'ช่วยให้เห็นการเปลี่ยนแปลงระยะสั้นแบบเดือนต่อเดือน\n\n'
                    'คำนวณอย่างไร?\n'
                    'เอายอด$labelเดือนนี้ ลบด้วยยอดเดือนก่อน แล้วหารด้วยยอด'
                    'เดือนก่อน คูณ 100 จะได้เป็น% ที่เพิ่มขึ้นหรือลดลง '
                    '(ถ้าเดือนก่อนเป็น 0 บาท จะโชว์เป็นส่วนต่างบาทแทน '
                    'เพราะหารด้วย 0 ไม่ได้)',
              ),
            ),
            if (yoy != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _comparisonCard(
                  context,
                  'เทียบปีก่อน (เดือนเดียวกัน)',
                  yoy,
                  previousLabel: 'ปีก่อน',
                  emptyHint: '',
                  infoTitle: 'เทียบปีก่อนคืออะไร?',
                  infoMessage:
                      'เทียบยอด$labelเดือนนี้กับเดือนเดียวกันของปีที่แล้ว '
                      'ช่วยให้เห็นแนวโน้มตามฤดูกาล เช่น หน้าร้อนมักใช้ไฟมากกว่าหน้าฝน\n\n'
                      'คำนวณอย่างไร?\n'
                      'เอายอด$labelเดือนนี้ ลบด้วยยอดเดือนเดียวกันของปีก่อน '
                      'แล้วหารด้วยยอดปีก่อน คูณ 100 จะได้เป็น% ที่เพิ่มขึ้นหรือลดลง',
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _comparisonCard(
          context,
          'เทียบค่าเฉลี่ย 6 เดือนล่าสุด',
          avg6,
          previousLabel: 'เฉลี่ย 6 เดือน',
          emptyHint:
              'ต้องมีบิลอย่างน้อย 3 เดือน (ตอนนี้มี ${bills.length} เดือน)',
          infoTitle: 'เทียบค่าเฉลี่ย 6 เดือนคืออะไร?',
          infoMessage:
              'เทียบยอด$labelเดือนนี้กับค่าเฉลี่ยของ 6 เดือนก่อนหน้า '
              'ช่วยให้เห็นภาพที่นิ่งกว่าเทียบเดือนก่อนเดือนเดียว เผื่อเดือนก่อน'
              'มีอะไรผิดปกติไปเอง\n\n'
              'คำนวณอย่างไร?\n'
              'เอายอด$labelของ 6 เดือนก่อนหน้ามารวมกัน แล้วหารด้วย 6 '
              'จะได้ค่าเฉลี่ย จากนั้นเอายอดเดือนนี้ลบค่าเฉลี่ยนั้น หารด้วย'
              'ค่าเฉลี่ย คูณ 100 จะได้เป็น% ที่เพิ่มขึ้นหรือลดลง '
              '(ถ้าเดือนไหนไม่มีบิลก็จะไม่ถูกนับรวมในค่าเฉลี่ย)',
        ),
        if (bills.isNotEmpty) ...[
          const SizedBox(height: 10),
          _forecastCard(context, forecast,
              lowConfidence: forecastLowConfidence,
              usesSeasonalCurve: usesSeasonalCurve),
          const SizedBox(height: 10),
          _multiMonthForecastCard(context, multiMonthForecast,
              lowConfidence: forecastLowConfidence,
              usesSeasonalCurve: usesSeasonalCurve),
        ],
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 16),
          _insightsCard(insights),
        ],
      ],
    );
  }

  String? _overviewSummary(ComparisonResult? mom, ComparisonResult? avg6) {
    if (mom == null && avg6 == null) return null;

    String momPart(ComparisonResult m) {
      if (m.isUnchanged) return '$labelเดือนนี้ไม่เปลี่ยนแปลงจากเดือนก่อน';
      final dir = m.isIncrease ? 'สูงขึ้น' : 'ลดลง';
      final pct = m.percentChange != null
          ? ' ${m.percentChange!.abs().toStringAsFixed(0)}%'
          : '';
      return '$labelเดือนนี้$dirจากเดือนก่อน$pct';
    }

    String avgPart(ComparisonResult a, {String? connector}) {
      final lead = connector ?? '';
      if (a.isUnchanged) return '$leadเท่ากับค่าเฉลี่ย 6 เดือนที่ผ่านมา';
      final dir = a.isIncrease ? 'สูงกว่า' : 'ต่ำกว่า';
      final pct = a.percentChange != null
          ? ' ${a.percentChange!.abs().toStringAsFixed(0)}%'
          : '';
      return '$lead$dirค่าเฉลี่ย 6 เดือนที่ผ่านมา$pct';
    }

    if (mom != null && avg6 != null) {
      final sameDirection = mom.isIncrease == avg6.isIncrease;
      final connector = sameDirection ? ' และ' : ' แต่';
      return '${momPart(mom)}$connector${avgPart(avg6, connector: '')}';
    } else if (mom != null) {
      return momPart(mom);
    } else {
      return '$labelเดือนนี้${avgPart(avg6!)}';
    }
  }

  Widget _overviewBanner(String summary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 16, color: _green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summary,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1B5E20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentCycleCard(BuildContext context) {
    final c = currentCycle!;
    final progressPercent = (c.progress * 100).toStringAsFixed(0);

    return Container(
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
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.timelapse, color: accentColor, size: 15),
              ),
              const SizedBox(width: 8),
              const Text('คาดการณ์ยอดบิลรอบนี้',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text('ผ่านมาแล้ว $progressPercent%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => showInfoDialog(
                  context,
                  title: 'ตัวเลขนี้คำนวณอย่างไร?',
                  message: 'คำนวณจากค่าใช้จ่ายเฉลี่ยต่อวันตั้งแต่ต้นรอบถึง'
                      'วันนี้ คูณด้วยจำนวนวันที่เหลือในรอบ แล้วบวกกับยอดที่'
                      'ใช้จริงไปแล้ว\n\n'
                      'หากใช้งานไม่สม่ำเสมอมาก (เช่น ต้นเดือนใช้น้อย ปลายเดือน'
                      'ใช้พุ่ง) ตัวเลขอาจคลาดเคลื่อนได้บ้าง',
                ),
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withValues(alpha: 0.12),
                  ),
                  child: const Text('!',
                      style: TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: c.progress,
              minHeight: 6,
              backgroundColor: _green.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(_green),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _cycleStat(
                    'ใช้ไปแล้ว', '${_fmt.format(c.currentCost)} บาท'),
              ),
              Expanded(
                child: _cycleStat(
                    'คาดว่าจะจบรอบที่', '${_fmt.format(c.forecastCost)} บาท',
                    highlight: true),
              ),
              Expanded(
                child: _cycleStat('เหลืออีก', '${c.remainingDays} วัน'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: DashboardStyles.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.speed, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ใช้ไป ${_fmtUnit.format(c.currentUnits)} $unitLabel '
                    '• คาดว่าจะใช้ทั้งสิ้น ${_fmtUnit.format(c.forecastUnits)} $unitLabel',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cycleStat(String label, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: highlight ? 15 : 13,
              color: highlight ? _green : Colors.black87,
            )),
      ],
    );
  }

  static const double _anomalyThresholdPercent = 70;

  Widget _comparisonCard(
    BuildContext context,
    String label,
    ComparisonResult? r, {
    required String previousLabel,
    String emptyHint = 'ไม่มีข้อมูลพอเทียบ',
    required String infoTitle,
    required String infoMessage,
  }) {
    final isAnomaly = r != null &&
        r.percentChange != null &&
        r.percentChange!.abs() >= _anomalyThresholdPercent;

    return Container(
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
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ),
              GestureDetector(
                onTap: () => showInfoDialog(
                  context,
                  title: infoTitle,
                  message: infoMessage,
                ),
                child: Icon(Icons.info_outline,
                    size: 14, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (r == null)
            Text(emptyHint,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500))
          else if (r.isUnchanged)
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.withValues(alpha: 0.12),
                  ),
                  child:
                      const Icon(Icons.remove, size: 15, color: Colors.grey),
                ),
                const SizedBox(width: 6),
                const Text('ไม่เปลี่ยนแปลง',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.grey)),
              ],
            )
          else ...[
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isAnomaly
                            ? Colors.orange
                            : (r.isIncrease
                                ? DashboardStyles.spikeUp
                                : DashboardStyles.spikeDown))
                        .withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    isAnomaly
                        ? Icons.warning_amber_rounded
                        : (r.isIncrease
                            ? Icons.arrow_upward
                            : Icons.arrow_downward),
                    size: 15,
                    color: isAnomaly
                        ? Colors.orange.shade800
                        : (r.isIncrease
                            ? DashboardStyles.spikeUp
                            : DashboardStyles.spikeDown),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  r.percentChange == null
                      ? '${_fmt.format(r.diff.abs())} บาท'
                      : '${r.percentChange!.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isAnomaly
                        ? Colors.orange.shade800
                        : (r.isIncrease
                            ? DashboardStyles.spikeUp
                            : DashboardStyles.spikeDown),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_fmt.format(r.currentValue)} บาท '
                '← $previousLabel ${_fmt.format(r.previousValue)} บาท',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),
            ),
            if (isAnomaly)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 13, color: Colors.orange.shade800),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        r.isIncrease
                            ? 'เปลี่ยนแปลงมากผิดปกติ ลองเช็คว่ามีเครื่องใช้ไฟฟ้าใหม่'
                                'หรือมีคนพักอาศัยเพิ่มไหม'
                            : 'เปลี่ยนแปลงมากผิดปกติ มักเกิดจากไม่อยู่บ้านทั้งเดือน'
                                'หรือมิเตอร์บันทึกคลาดเคลื่อน ลองเช็คบิลอีกครั้ง',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.orange.shade800,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  static const _thaiMonthShort = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  String _seasonName(int month) {
    if (month >= 3 && month <= 5) return 'ช่วงฤดูร้อน';
    if (month >= 6 && month <= 10) return 'ช่วงฤดูฝน';
    return 'ช่วงฤดูหนาว';
  }

  String _seasonReasonText(int month, double factor) {
    final monthName = _thaiMonthShort[month - 1];
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

  Widget _forecastCard(
    BuildContext context,
    double forecast, {
    required bool lowConfidence,
    required bool usesSeasonalCurve,
  }) {
    final comparedToLastBill =
        bills.isNotEmpty ? selector(bills.last) : null;
    final comparison = comparedToLastBill != null && comparedToLastBill > 0
        ? ComparisonResult(
            currentValue: forecast, previousValue: comparedToLastBill)
        : null;
    // เดือนก่อนหน้าที่เอามาเทียบเอง "ต่ำ/สูงผิดปกติ" ไหม (เทียบง่ายๆ กับ
    // ค่าเฉลี่ย 6 เดือนล่าสุด ถ้ามี) — ถ้าใช่ ผลต่าง % ที่โชว์ด้านล่างจะดู
    // เกินจริงไปมาก ต้องเตือนผู้ใช้ไว้ก่อน ไม่ให้ตกใจ/เข้าใจผิดว่าคาดการณ์พลาด
    final avg6ForAnomalyCheck = bills.length >= 3
        ? analysisService.compareToAverage(bills, selector: selector)
        : null;
    final lastBillIsAnomalousBase = avg6ForAnomalyCheck != null &&
        avg6ForAnomalyCheck.percentChange != null &&
        avg6ForAnomalyCheck.percentChange!.abs() >= 70;

    final targetMonth = bills.isNotEmpty
        ? DateTime(bills.last.year, bills.last.month + 1, 1).month
        : null;
    final seasonalFactor = (usesSeasonalCurve && targetMonth != null)
        ? analysisService.seasonalFactorForMonth(
            month: targetMonth,
            area: area,
            meterType: meterType,
            isWater: isWater,
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: _green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      targetMonth != null
                          ? 'คาดการณ์เดือนหน้า • ${_thaiMonthShort[targetMonth - 1]}'
                          : 'คาดการณ์เดือนหน้า',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text('${_fmt.format(forecast)} บาท',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: _green)),
                    if (seasonalFactor != null && targetMonth != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _seasonReasonText(targetMonth, seasonalFactor),
                          style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade700,
                              height: 1.4),
                        ),
                      ),
                    // เดือนฐานที่ใช้เทียบ (บิลล่าสุด) ผิดปกติจากค่าเฉลี่ยมาก
                    // เกินไป → เตือนไว้ว่าตัวเลข %/บาทที่เทียบด้านล่างอาจดู
                    // เกินจริง แทนที่จะปล่อยให้ผู้ใช้ตกใจว่าคาดการณ์พลาดมาก
                    if (lastBillIsAnomalousBase)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'เดือนล่าสุดที่ใช้เทียบมีค่าผิดปกติจากค่าเฉลี่ย '
                          'ตัวเลขเทียบด้านล่างอาจดูต่างจากปกติมากกว่าที่ควรจะเป็น',
                          style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.orange.shade800,
                              height: 1.4),
                        ),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => showInfoDialog(
                  context,
                  title: 'ตัวเลขนี้คำนวณอย่างไร?',
                  message: usesSeasonalCurve
                      ? 'เอาค่าเฉลี่ย$labelย้อนหลังไม่กี่เดือนล่าสุดของคุณ '
                          'มาปรับด้วยรูปแบบฤดูกาล (เช่น เดือนร้อนมักใช้ไฟ'
                          'มากกว่าเดือนหนาว) เพื่อทายเดือนถัดไปให้ใกล้เคียง'
                          'ความจริงมากกว่าการลากเส้นแนวโน้มตรงๆ\n\n'
                          'รูปแบบฤดูกาลนี้ผสมจากข้อมูลจำลองกับข้อมูลผู้ใช้จริง'
                          'เท่าที่มี ยิ่งมีผู้ใช้จริงสะสมข้อมูลมากขึ้น ตัวเลข'
                          'นี้จะยิ่งแม่นยำขึ้นเรื่อยๆ'
                      : 'ประมาณแนวโน้มจากยอด$labelย้อนหลังทั้งหมดที่บันทึกไว้ '
                          'แล้วลากเส้นแนวโน้มนั้นต่อไปยังเดือนถัดไป\n\n'
                          'ยิ่งมีข้อมูลสะสมหลายเดือน ตัวเลขนี้จะยิ่งแม่นยำขึ้น',
                ),
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withValues(alpha: 0.15),
                  ),
                  child: const Text('!',
                      style: TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          if (comparison != null && !comparison.isUnchanged) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  comparison.isIncrease
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 14,
                  color: comparison.isIncrease
                      ? DashboardStyles.spikeUp
                      : DashboardStyles.spikeDown,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${comparison.isIncrease ? 'สูงกว่า' : 'ต่ำกว่า'}เดือนนี้ประมาณ '
                    '${comparison.percentChange != null ? '${comparison.percentChange!.abs().toStringAsFixed(0)}% ' : ''}'
                    '(${comparison.isIncrease ? '+' : '-'}${_fmt.format(comparison.diff.abs())} บาท)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: comparison.isIncrease
                          ? DashboardStyles.spikeUp
                          : DashboardStyles.spikeDown,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (lowConfidence) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ประมาณการเบื้องต้น (มีข้อมูล ${bills.length} เดือน)',
                style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _trendSummaryText(List<double> historySlice, List<double> forecasts) {
    if (forecasts.length < 2) {
      return 'แนวโน้มช่วงถัดไปอ้างอิงจากรูปแบบฤดูกาลและค่าเฉลี่ยล่าสุดของคุณ';
    }
    final first = forecasts.first;
    final last = forecasts.last;
    final diffPercent =
        first == 0 ? 0 : ((last - first) / first * 100).abs().round();

    if (last > first * 1.05) {
      return 'มีแนวโน้มขยับขึ้นอีกประมาณ $diffPercent% ในช่วง '
          '${forecasts.length} เดือนที่คาดการณ์ไว้';
    }
    if (last < first * 0.95) {
      return 'มีแนวโน้มลดลงอีกประมาณ $diffPercent% ในช่วง '
          '${forecasts.length} เดือนที่คาดการณ์ไว้';
    }
    return 'ค่อนข้างทรงตัวตลอดช่วง ${forecasts.length} เดือนที่คาดการณ์ไว้';
  }

  Widget _multiMonthForecastCard(
    BuildContext context,
    List<double> forecasts, {
    required bool lowConfidence,
    required bool usesSeasonalCurve,
  }) {
    if (bills.isEmpty || forecasts.isEmpty) return const SizedBox.shrink();

    final lastBill = bills.last;
    final historyValues = bills.map(selector).toList();
    final historyStart =
        historyValues.length > 6 ? historyValues.length - 6 : 0;
    final historySlice = historyValues.sublist(historyStart);

    final historySpots = List.generate(
      historySlice.length,
      (i) => FlSpot(i.toDouble(), historySlice[i]),
    );
    final forecastSpots = [
      FlSpot((historySlice.length - 1).toDouble(), historySlice.last),
      ...List.generate(
        forecasts.length,
        (i) => FlSpot((historySlice.length + i).toDouble(), forecasts[i]),
      ),
    ];

    final allValues = [...historySlice, ...forecasts];
    final maxVal = allValues.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 10.0 : maxVal * 1.2;

    final labels = <String>[
      for (int i = 0; i < historySlice.length; i++)
        '${bills[historyStart + i].month}/${bills[historyStart + i].year % 100}',
      for (int i = 0; i < forecasts.length; i++)
        () {
          final d = DateTime(lastBill.year, lastBill.month + i + 1, 1);
          return '${d.month}/${d.year % 100}';
        }(),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              const Icon(Icons.trending_up, color: _green, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('คาดการณ์ ${forecasts.length} เดือนข้างหน้า',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
              GestureDetector(
                onTap: () => showInfoDialog(
                  context,
                  title: 'ตัวเลขนี้คำนวณอย่างไร?',
                  message: usesSeasonalCurve
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
                          'มากกว่าใช้เป็นตัวเลขที่แม่นยำ',
                ),
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withValues(alpha: 0.15),
                  ),
                  child: const Text('!',
                      style: TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const chartHeight = 140.0;
              const bottomAxisHeight = 22.0;
              const plotHeight = chartHeight - bottomAxisHeight;
              final chartWidth = constraints.maxWidth;
              final xIndexMax =
                  (labels.length - 1).clamp(1, 999999).toDouble();
              final todayX = historySlice.length - 0.5;

              return SizedBox(
                height: chartHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: maxY,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (v) => FlLine(
                              color: Colors.grey.shade200, strokeWidth: 1),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: bottomAxisHeight,
                              getTitlesWidget: (value, meta) {
                                final i = value.toInt();
                                if (i < 0 || i >= labels.length) {
                                  return const SizedBox.shrink();
                                }
                                final isForecast = i >= historySlice.length;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    labels[i],
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: isForecast
                                          ? _green
                                          : Colors.grey.shade600,
                                      fontWeight: isForecast
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        extraLinesData: ExtraLinesData(
                          verticalLines: [
                            VerticalLine(
                              x: todayX,
                              color: Colors.grey.shade300,
                              strokeWidth: 1,
                              dashArray: const [4, 3],
                              label: VerticalLineLabel(
                                show: true,
                                alignment: Alignment.topCenter,
                                padding: const EdgeInsets.only(bottom: 2),
                                style: TextStyle(
                                    fontSize: 9, color: Colors.grey.shade500),
                                labelResolver: (_) => 'วันนี้',
                              ),
                            ),
                          ],
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: historySpots,
                            isCurved: false,
                            color: Colors.grey.shade500,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: forecastSpots,
                            isCurved: false,
                            color: _green,
                            barWidth: 2,
                            dashArray: const [6, 4],
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, bar, index) =>
                                  FlDotCirclePainter(
                                radius: index == 0 ? 0 : 3,
                                color: _green,
                                strokeWidth: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (int i = 0; i < forecasts.length; i++)
                      Positioned(
                        left: (((historySlice.length + i) / xIndexMax) *
                                chartWidth) -
                            22,
                        top: (plotHeight -
                                (forecasts[i] / maxY) * plotHeight) -
                            18,
                        width: 44,
                        child: Text(
                          _fmt.format(forecasts[i]),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _green,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _trendSummaryText(historySlice, forecasts),
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          if (lowConfidence) ...[
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ประมาณการเบื้องต้น (มีข้อมูล ${bills.length} เดือน) '
                'ยิ่งเดือนไกลยิ่งไม่แน่นอน',
                style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _insightsCard(List<AnalysisInsight> insights) {
    return Container(
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
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.lightbulb_outline,
                    size: 15, color: _green),
              ),
              const SizedBox(width: 8),
              const Text('ข้อสังเกต',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          ...insights.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _insightColor(i.level).withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        _insightIcon(i.level),
                        size: 14,
                        color: _insightColor(i.level),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(i.text,
                                style: const TextStyle(
                                    fontSize: 12.5, height: 1.4)),
                          ),
                          if (i.showApplianceCta &&
                              onViewAppliances != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: GestureDetector(
                                onTap: onViewAppliances,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('ดูอุปกรณ์ที่ใช้ไฟมากสุด',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: _green)),
                                    SizedBox(width: 2),
                                    Icon(Icons.arrow_forward_ios,
                                        size: 10, color: _green),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  IconData _insightIcon(InsightLevel level) {
    switch (level) {
      case InsightLevel.good:
        return Icons.check_circle;
      case InsightLevel.warning:
        return Icons.warning_amber_rounded;
      case InsightLevel.neutral:
        return Icons.info_outline;
    }
  }

  Color _insightColor(InsightLevel level) {
    switch (level) {
      case InsightLevel.good:
        return _green;
      case InsightLevel.warning:
        return Colors.orange.shade800;
      case InsightLevel.neutral:
        return Colors.grey.shade600;
    }
  }
}