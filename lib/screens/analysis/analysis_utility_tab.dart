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
  });

  @override
  Widget build(BuildContext context) {
    final mom = analysisService.compareMoM(bills, selector: selector);
    final yoy = analysisService.compareYoY(bills, selector: selector);
    final avg6 = analysisService.compareToAverage(bills, selector: selector);
    final forecast =
        analysisService.forecastNextMonth(bills, selector: selector);

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
              child: _comparisonCard(
                context,
                'เทียบปีก่อน (เดือนเดียวกัน)',
                yoy,
                emptyHint:
                    'ยังไม่มีบิลเดือนเดียวกันของปีก่อน เก็บข้อมูลต่อให้ครบ 1 ปีจะเริ่มเทียบได้',
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
        ),
        const SizedBox(height: 10),
        _comparisonCard(
          context,
          'เทียบค่าเฉลี่ย 6 เดือนล่าสุด',
          avg6,
          emptyHint:
              'ต้องมีบิลอย่างน้อย 3 เดือน (ตอนนี้มี ${bills.length} เดือน)',
          fullWidth: true,
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
        // ไม่มีบิลเลยสักเดือน = พยากรณ์ไม่มีความหมายอะไรทั้งสิ้น (ไม่ใช่แค่
        // "ความมั่นใจต่ำ") ซ่อนการ์ดนี้ไปเลยดีกว่าโชว์ "0.00 บาท" ซึ่งดู
        // เหมือนระบบฟันธงว่าเดือนหน้าจะไม่มีค่าใช้จ่าย ทั้งที่จริงคือยังไม่มี
        // ข้อมูลให้คำนวณ — กราฟเทรนด์ด้านบนมี empty-state อธิบายเรื่องนี้
        // ให้ผู้ใช้แล้ว ไม่ต้องพูดซ้ำอีกรอบในการ์ดนี้
        if (bills.isNotEmpty) ...[
          const SizedBox(height: 10),
          _forecastCard(context, forecast,
              lowConfidence: forecastLowConfidence),
        ],
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 16),
          _insightsCard(insights),
        ],
      ],
    );
  }

  // ----- ประโยคสรุปภาพรวม 1 บรรทัด รวม "เทียบเดือนก่อน" + "เทียบค่าเฉลี่ย
  // 6 เดือน" เข้าด้วยกัน เพื่อให้ผู้ใช้เห็นภาพรวมทันทีโดยไม่ต้องไล่อ่านทีละ
  // การ์ดเองว่าสรุปแล้วเดือนนี้ "ดีขึ้นจริงไหม" (เช่น ลดลงจากเดือนก่อนก็จริง
  // แต่ถ้ายังสูงกว่าค่าเฉลี่ยอยู่ ก็ยังไม่ใช่ข่าวดีทั้งหมด) -----
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
      // ถ้าทิศทางเทียบเดือนก่อน กับเทียบค่าเฉลี่ย ไปคนละทาง (เช่น ลดลงจาก
      // เดือนก่อน แต่ยังสูงกว่าค่าเฉลี่ย) ใช้ "แต่" เพื่อสื่อความขัดแย้งนั้น
      // ให้ผู้ใช้เห็นชัดว่ายังวางใจไม่ได้เต็มที่ ถ้าไปทางเดียวกันใช้ "และ"
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

  // ----- การ์ดพยากรณ์ยอดบิลรอบปัจจุบัน (Moving Average ถึงวันตัดรอบ) -----
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
              const Icon(Icons.timelapse, color: _green, size: 18),
              const SizedBox(width: 6),
              const Text('พยากรณ์ยอดบิลรอบนี้',
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

  Widget _comparisonCard(
    BuildContext context,
    String label,
    ComparisonResult? r, {
    String emptyHint = 'ไม่มีข้อมูลพอเทียบ',
    bool fullWidth = false,
    required String infoTitle,
    required String infoMessage,
  }) {
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
              // ปุ่ม (i) ใช้ showInfoDialog ตัวเดียวกับที่ใช้ทั่วแอป (ดู
              // การ์ดพยากรณ์รอบปัจจุบันด้านบน) ใส่ให้ครบทุกการ์ดเทียบเพื่อ
              // ความสม่ำเสมอ แทนที่จะมีแค่การ์ดเดียวที่อธิบายวิธีคำนวณ
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
            // โชว์ "progress" ว่าต้องเก็บข้อมูลเพิ่มอีกแค่ไหนถึงจะเทียบได้
            // แทนข้อความเฉยๆ ว่าไม่มีข้อมูล ให้ผู้ใช้ใหม่รู้ว่าต้องรออะไร
            Text(emptyHint,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: r.isUnchanged
                      ? const Row(
                          children: [
                            Icon(Icons.remove, size: 16, color: Colors.grey),
                            SizedBox(width: 4),
                            Text('ไม่เปลี่ยนแปลง',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.grey)),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  r.isIncrease
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  size: 16,
                                  color: r.isIncrease
                                      ? DashboardStyles.spikeUp
                                      : DashboardStyles.spikeDown,
                                ),
                                const SizedBox(width: 4),
                                // ตัวเลขหลัก: % ถ้าคำนวณได้ ไม่งั้นค่อย fallback
                                // เป็นบาท (กรณีค่าที่เทียบเป็น 0 หารไม่ได้)
                                Text(
                                  r.percentChange == null
                                      ? '${_fmt.format(r.diff.abs())} บาท'
                                      : '${r.percentChange!.abs().toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: r.isIncrease
                                        ? DashboardStyles.spikeUp
                                        : DashboardStyles.spikeDown,
                                  ),
                                ),
                              ],
                            ),
                            // โชว์ผลต่างเป็นบาทควบคู่ไปด้วยเสมอ (ไม่ใช่แค่ %)
                            // ยกเว้นตอนที่ % คำนวณไม่ได้อยู่แล้วซึ่งบาทถูก
                            // โชว์เป็นตัวหลักไปแล้วด้านบน ไม่ต้องซ้ำ ใช้สี
                            // เดียวกับลูกศร/ตัวเลข % เพื่อให้อ่านเป็นชุดเดียวกัน
                            if (r.percentChange != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '${r.isIncrease ? '+' : '-'}'
                                  '${_fmt.format(r.diff.abs())} บาท',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: r.isIncrease
                                        ? DashboardStyles.spikeUp
                                        : DashboardStyles.spikeDown,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                if (fullWidth)
                  Text('เฉลี่ย ${_fmt.format(r.previousValue)} บาท',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade500)),
              ],
            ),
        ],
      ),
    );
  }

  // ----- การ์ดพยากรณ์ "เดือนถัดไป" ด้วย Linear Regression จากบิลย้อนหลัง
  // ทั้งหมด (ชื่อเทคนิคเก็บไว้แค่ในคอมเมนต์นี้กับ thesis report เท่านั้น —
  // ฝั่ง UI ใช้ภาษาคนล้วน ให้ผู้ใช้ทั่วไปเข้าใจได้โดยไม่ต้องรู้จักศัพท์สถิติ) -----
  Widget _forecastCard(
    BuildContext context,
    double forecast, {
    required bool lowConfidence,
  }) {
    // เทียบกับยอดบิลจริงเดือนล่าสุด เพื่อบอกเป็นประโยคปกติว่าเดือนหน้า
    // "คาดว่าจะสูง/ต่ำกว่าเดือนนี้" แทนที่จะโชว์ตัวเลขลอยๆ ให้ผู้ใช้ไปตีความเอง
    final comparedToLastBill =
        bills.isNotEmpty ? selector(bills.last) : null;
    final comparison = comparedToLastBill != null && comparedToLastBill > 0
        ? ComparisonResult(
            currentValue: forecast, previousValue: comparedToLastBill)
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
                    const Text('คาดการณ์เดือนหน้า',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('${_fmt.format(forecast)} บาท',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: _green)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => showInfoDialog(
                  context,
                  title: 'ตัวเลขนี้คำนวณอย่างไร?',
                  message:
                      'ประมาณแนวโน้มจากยอด$labelย้อนหลังทั้งหมดที่บันทึกไว้ '
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

  // ----- การ์ดข้อสังเกต/คำแนะนำที่วิเคราะห์มาจากข้อมูลจริง -----
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
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: _green),
              SizedBox(width: 6),
              Text('ข้อสังเกต',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          ...insights.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _insightIcon(i.level),
                      size: 16,
                      color: _insightColor(i.level),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.text,
                              style: const TextStyle(
                                  fontSize: 12.5, height: 1.4)),
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