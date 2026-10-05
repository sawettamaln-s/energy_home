part of 'analysis_screen.dart';

// ==================== Tab อุปกรณ์ ====================
// สัดส่วนการใช้ไฟของอุปกรณ์ (ประมาณการจากกำลังไฟ × ตารางการใช้งาน) แสดงเป็น
// แถบแนวนอนเรียงจากมากไปน้อย อ่านชื่อ/สัดส่วน/หน่วย/บาทได้ในแถวเดียว
class _ApplianceTab extends StatelessWidget {
  final List<ApplianceModel> appliances;
  final AnalysisService analysisService;
  // อัตราค่าไฟต่อหน่วยเดียวกับหน้าอุปกรณ์ (จากบิลล่าสุดของผู้ใช้)
  final ApplianceRate rate;

  const _ApplianceTab({
    required this.appliances,
    required this.analysisService,
    required this.rate,
  });

  @override
  Widget build(BuildContext context) {
    final breakdown = analysisService.applianceBreakdown(appliances, avgRatePerUnit: rate.perUnit);

    if (breakdown.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.v32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconBadge(icon: Icons.electrical_services_rounded, color: Colors.grey.shade500, size: 64),
                    const SizedBox(height: AppSpacing.v16),
                    const Text('ยังไม่มีอุปกรณ์ที่ตั้งตารางการใช้งาน',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: AppTypography.s14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    const SizedBox(height: AppSpacing.v6),
                    Text('เพิ่มอุปกรณ์และเวลาใช้งานที่แท็บอุปกรณ์ เพื่อดูว่าเครื่องไหนใช้ไฟมากที่สุดค่ะ',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final insights = analysisService.generateApplianceInsights(breakdown);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.v16),
      children: [
        FadeSlideIn(child: _ApplianceBreakdownCard(breakdown: breakdown, rate: rate)),
        if (insights.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.v16),
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: _InsightsCard(insights: insights),
          ),
        ],
      ],
    );
  }
}

// =====================================================================
// การ์ดสัดส่วนอุปกรณ์ — โชว์ 5 อันดับแรกก่อน มีปุ่ม "ดูทั้งหมด" ถ้ามีมากกว่านั้น
// =====================================================================
class _ApplianceBreakdownCard extends StatefulWidget {
  final List<ApplianceUsage> breakdown;
  final ApplianceRate rate;

  const _ApplianceBreakdownCard({required this.breakdown, required this.rate});

  @override
  State<_ApplianceBreakdownCard> createState() => _ApplianceBreakdownCardState();
}

class _ApplianceBreakdownCardState extends State<_ApplianceBreakdownCard> {
  static const _collapsedCount = 5;
  static final _kwhFmt = NumberFormat('#,##0.#');
  static final _costFmt = NumberFormat('#,##0');

  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final breakdown = widget.breakdown;
    final hasMore = breakdown.length > _collapsedCount;
    final visible = _showAll || !hasMore ? breakdown : breakdown.take(_collapsedCount).toList();
    final totalKwh = breakdown.fold<double>(0, (sum, u) => sum + u.kWh);
    final totalCost = breakdown.fold<double>(0, (sum, u) => sum + u.cost);
    const colors = AppColors.pieChartPalette;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.electrical_services_rounded, color: AppColors.primaryGreen, size: 34),
              const SizedBox(width: AppSpacing.v10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('อุปกรณ์ที่ใช้ไฟ',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: AppTypography.s15, color: AppColors.textDark)),
                    Text(
                      'ประมาณการต่อเดือน รวม ${_kwhFmt.format(totalKwh)} หน่วย · ${_costFmt.format(totalCost)} บาท',
                      style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              _InfoButton(onTap: () => showApplianceEstimateInfoDialog(context, rate: widget.rate)),
            ],
          ),
          const SizedBox(height: AppSpacing.v8),
          for (final (i, u) in visible.indexed) ...[
            if (i > 0) const Divider(),
            _row(u, colors[i % colors.length]),
          ],
          if (hasMore)
            TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                textStyle: const TextStyle(
                    fontFamily: AppTheme.fontFamily, fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600),
              ),
              child: Text(_showAll ? 'ย่อรายการ' : 'ดูทั้งหมด (${breakdown.length})'),
            ),
        ],
      ),
    );
  }

  // แถวอุปกรณ์ 1 รายการ: ชื่อ + % (บรรทัดบน), แถบสัดส่วน, หน่วยและบาท (บรรทัดล่าง)
  Widget _row(ApplianceUsage u, Color color) {
    final share = (u.percentOfTotal / 100).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.v10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(u.appliance.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
              ),
              const SizedBox(width: AppSpacing.v8),
              Text('${u.percentOfTotal.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: AppTypography.s14, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: AppSpacing.v6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.v4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: AppSpacing.v6),
          Text('${_kwhFmt.format(u.kWh)} หน่วย · ${_costFmt.format(u.cost)} บาท',
              style: TextStyle(
                  fontSize: AppTypography.s11_5,
                  color: Colors.grey.shade600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
