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
    // คาดการณ์ฝั่ง "หน่วยที่ใช้" (กราฟเทรนด์สลับโหมดได้) — เส้นฤดูกาลสร้างจาก
    // ยอดหน่วยอยู่แล้ว (tool/forecast_synth) ยอดรวมทั้งเดือนไม่แยก On/Off-Peak
    final multiMonthUsedForecast = analysisService.forecastNextMonths(
      bills,
      selector: usedSelector,
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


    // การ์ดเทียบค่าเฉลี่ย 6 เดือน — ใช้ได้ทั้งเป็นการ์ดเต็มความกว้าง (มีข้อมูลปีก่อน)
    // และเป็นการ์ดช่องขวาข้างเทียบเดือนก่อน (ยังไม่มีข้อมูลปีก่อน)
    Widget avg6Card(String cardLabel) => _comparisonCard(
          context,
          cardLabel,
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
          decreaseWord: 'ประหยัดกว่าปกติ',
          increaseWord: 'ใช้มากกว่าปกติ',
          sameLabel: 'เท่ากับค่าเฉลี่ย',
        );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
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
          costForecast: multiMonthForecast,
          usedForecast: multiMonthUsedForecast,
          forecastLowConfidence: forecastLowConfidence,
          usesSeasonalCurve: usesSeasonalCurve,
        ),
        const SizedBox(height: 16),
        // แถวบน: เทียบเดือนก่อน | เทียบปีก่อน — ถ้ายังไม่มีข้อมูลปีก่อน (ซ่อนอยู่)
        // ให้ "เทียบค่าเฉลี่ย 6 เดือน" ขึ้นมาอยู่ช่องนั้นแทน และไม่ต้องมีการ์ด
        // เต็มความกว้างด้านล่างอีก IntrinsicHeight + stretch ทำให้การ์ดสองใบ
        // ในแถวเดียวกันสูงเท่ากันเสมอ ไม่ว่าเนื้อหาข้างในจะยาวไม่เท่ากัน
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(width: 10),
              Expanded(
                child: yoy != null
                    ? _comparisonCard(
                        context,
                        'เทียบปีก่อน',
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
                      )
                    : avg6Card('เทียบค่าเฉลี่ย 6 เดือน'),
              ),
            ],
          ),
        ),
        if (yoy != null) ...[
          const SizedBox(height: 10),
          avg6Card('เทียบค่าเฉลี่ย 6 เดือนล่าสุด'),
        ],
        if (bills.isNotEmpty) ...[
          const SizedBox(height: 10),
          _forecastCard(context, forecast,
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
    // ถ้อยคำหน้าตัวเลข % — ตัวเทียบค่าเฉลี่ยส่งคำของตัวเองมา
    // ("ประหยัดกว่าปกติ" แทน "ใช้น้อยลง")
    String decreaseWord = 'ใช้น้อยลง',
    String increaseWord = 'ใช้มากขึ้น',
    // เท่ากันเป๊ะ → ข้อความเดียว (เลือกคำเดียวไม่ซ้ำซ้อน) การ์ดยังมีแถวค่าอ้างอิง
    // เหมือนการ์ดอื่น ความสูงจึงเท่ากัน
    String sameLabel = 'ไม่เปลี่ยนแปลง',
  }) {
    final isAnomaly = r != null &&
        r.percentChange != null &&
        r.percentChange!.abs() >= _anomalyThresholdPercent;

    // สีตามความหมายเดิมของการ์ด: ลด = เขียว, เพิ่ม = แดง,
    // เปลี่ยนมากผิดปกติ = ส้ม, เท่ากัน/ไม่มีข้อมูล = เทา
    final Color tone = r == null || r.isUnchanged
        ? Colors.grey.shade600
        : isAnomaly
            ? Colors.orange.shade800
            : (r.isIncrease ? DashboardStyles.spikeUp : DashboardStyles.spikeDown);
    final IconData icon = r == null || r.isUnchanged
        ? Icons.remove
        : isAnomaly
            ? Icons.warning_amber_rounded
            : (r.isIncrease ? Icons.trending_up : Icons.trending_down);

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
          // หัวข้อการ์ด: ไอคอนเทรนด์ในกรอบสีจาง + ชื่อหัวข้อ — ความสูงคงที่
          // (รองรับหัวข้อ 2 บรรทัดในการ์ดครึ่งจอ) ให้บรรทัดค่าด้านล่างของ
          // การ์ดข้างกันอยู่ระดับเดียวกัน
          SizedBox(
            height: 34,
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: tone),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: Colors.grey.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => showInfoDialog(
                    context,
                    title: infoTitle,
                    message: infoMessage,
                  ),
                  child: Icon(Icons.info_outline,
                      size: 15, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (r == null)
            Text(emptyHint,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500))
          else ...[
            // FittedBox กันข้อความยาว (เช่น "ประหยัดกว่าปกติ 15.2%") ล้นการ์ดช่องแคบ
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: r.isUnchanged
                  ? Text(sameLabel,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                          color: tone))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          r.isIncrease ? increaseWord : decreaseWord,
                          style: TextStyle(fontSize: 12, color: tone),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          r.percentChange == null
                              ? '${_fmt.format(r.diff.abs())} บาท'
                              : '${r.percentChange!.abs().toStringAsFixed(1)}%',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 20,
                              color: tone),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            // แถวค่าอ้างอิง: ชื่อสิ่งที่ใช้เทียบ (ซ้าย) กับยอดของมัน (ขวา)
            Divider(height: 1, thickness: 0.5, color: Colors.grey.shade300),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(previousLabel,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Text(_fmt.format(r.previousValue),
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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

  // ไอคอนฤดูกาลของเดือนเป้าหมาย — แบ่งช่วงเดียวกับ _seasonName ด้านบน
  _Season _seasonFor(int month) {
    if (month >= 3 && month <= 5) return _Season.summer;
    if (month >= 6 && month <= 10) return _Season.rainy;
    return _Season.cool;
  }

  // ไอคอน + สีของแต่ละฤดู — ใช้ไอคอน Material ในกรอบมนสีอ่อน สไตล์เดียวกับ
  // การ์ด "ข้อสังเกต" (แทนไอคอนที่วาดเองด้วย CustomPainter เดิม)
  (IconData, Color) _seasonVisual(_Season season) {
    switch (season) {
      case _Season.summer:
        return (Icons.wb_sunny_rounded, const Color(0xFFF57C00));
      case _Season.rainy:
        return (Icons.umbrella_rounded, const Color(0xFF1E88E5));
      case _Season.cool:
        return (Icons.ac_unit_rounded, const Color(0xFF0097A7));
    }
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

    final Color? deltaTone = comparison == null
        ? null
        : (comparison.isUnchanged
            ? Colors.grey.shade600
            : (comparison.isIncrease
                ? DashboardStyles.spikeUp
                : DashboardStyles.spikeDown));

    final (IconData badgeIcon, Color badgeColor) = targetMonth != null
        ? _seasonVisual(_seasonFor(targetMonth))
        : (Icons.insights, _green);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      // ทุกอย่างในการ์ดชิดขอบซ้ายเส้นเดียวกัน — หัวการ์ด (ไอคอน/ชื่อ/ปุ่มข้อมูล)
      // อยู่บรรทัดเดียวเสมอ ปุ่มข้อมูลจึงไม่เลื่อนตามความสูงของข้อความด้านล่าง
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(badgeIcon, size: 20, color: badgeColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  targetMonth != null
                      ? 'คาดการณ์เดือนหน้า • ${_thaiMonthShort[targetMonth - 1]}'
                      : 'คาดการณ์เดือนหน้า',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
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
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.info_outline_rounded,
                      size: 20, color: _green.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('${_fmt.format(forecast)} บาท',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 24, color: _green)),
          if (seasonalFactor != null && targetMonth != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _seasonReasonText(targetMonth, seasonalFactor),
                style: TextStyle(
                    fontSize: 11.5, color: Colors.grey.shade700, height: 1.4),
              ),
            ),
          // ไม่ใส่หน้าอารมณ์ในบรรทัดนี้ เพราะการ์ดมีไอคอนสภาพอากาศอยู่แล้ว
          if (comparison != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    comparison.isUnchanged
                        ? Icons.trending_flat_rounded
                        : (comparison.isIncrease
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded),
                    size: 16,
                    color: deltaTone,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    comparison.isUnchanged
                        ? 'ไม่เปลี่ยนแปลงจากเดือนนี้'
                        : '${comparison.isIncrease ? 'สูงกว่า' : 'ประหยัดกว่า'}เดือนนี้ประมาณ '
                            '${comparison.percentChange != null ? '${comparison.percentChange!.abs().toStringAsFixed(0)}% ' : ''}'
                            '(${comparison.isIncrease ? '+' : '-'}${_fmt.format(comparison.diff.abs())} บาท)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: deltaTone,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // เดือนฐานที่ใช้เทียบ (บิลล่าสุด) ผิดปกติจากค่าเฉลี่ยมากเกินไป → เตือนไว้ว่า
          // ตัวเลข %/บาทที่เทียบอาจดูเกินจริง แทนที่จะปล่อยให้ผู้ใช้ตกใจว่าคาดการณ์พลาดมาก
          // (หน้าตาเดียวกับกล่องเตือนในการ์ดเปรียบเทียบ)
          if (lastBillIsAnomalousBase)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                      'เดือนล่าสุดที่ใช้เทียบมีค่าผิดปกติจากค่าเฉลี่ย '
                      'ตัวเลขเทียบด้านบนอาจดูต่างจากปกติมากกว่าที่ควรจะเป็น',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.orange.shade800,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if (lowConfidence) ...[
            const SizedBox(height: 10),
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

// =====================================================================
// ไอคอนฤดูกาลของการ์ดคาดการณ์เดือนหน้า: ร้อน = พระอาทิตย์, ฝน = ร่ม,
// หนาว = เกล็ดหิมะ (ช่วงเดือนตรงกับ _seasonName)
enum _Season { summer, rainy, cool }