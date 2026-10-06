import 'package:flutter/material.dart';

import '../../../utils/thai_date_utils.dart';
import '../../../widgets/ui/animated_amount.dart';
import '../dashboard_loader.dart';
import '../dashboard_styles.dart';

// =====================================================================
// การ์ดสรุปบิลรอบนี้ — การ์ดเด่นบนสุด แสดงเฉพาะข้อเท็จจริงของรอบนี้
// (รายละเอียดแยกไฟ/น้ำอยู่ที่ MeterSummaryCard และรายจ่ายประจำที่
// FixedCostTile ด้านล่าง):
//   1) ช่วงวันของรอบ + เดือนที่ออกบิล
//   2) ยอดที่ใช้ไปแล้ว พร้อมบรรทัดบอกที่มา (ค่าไฟ + ค่าน้ำ และรายจ่ายประจำถ้ามี)
//      และชิป "ดูคาดการณ์" พาไปแท็บวิเคราะห์ — หน้าหลักไม่แสดงยอดคาดการณ์เอง
//   3) แถบความคืบหน้าของรอบ: วันที่เท่าไรจากทั้งหมด และเหลืออีกกี่วัน
// =====================================================================
class BillHeroCard extends StatelessWidget {
  final DashboardData data;
  final int remainingDays;
  final int daysElapsed;
  final int cycleLengthDays;
  // แตะชิป "ดูคาดการณ์" — null = ไม่แสดงชิป
  final VoidCallback? onViewForecast;

  const BillHeroCard({
    super.key,
    required this.data,
    required this.remainingDays,
    required this.daysElapsed,
    required this.cycleLengthDays,
    this.onViewForecast,
  });

  String _shortDate(DateTime d) => '${d.day} ${thaiMonthsShort[d.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final user = data.user;
    final cycleEnd = data.cycleEnd;
    final fixedCost = data.billFixedCost;
    final usedSoFar =
        data.currentElectricityCost + data.currentWaterCost + fixedCost;
    // ผู้ใช้ใหม่ที่ยังไม่ได้ตั้งวันตัดรอบบิล ยังไม่มีรอบจริงให้นับวัน
    final cycleReady = user?.billingDayConfigured ?? true;
    final progress =
        cycleLengthDays > 0 ? daysElapsed / cycleLengthDays : 0.0;
    // วันสุดท้ายของรอบ = วันก่อนวันตัดรอบครั้งถัดไป
    final lastDay = cycleEnd.subtract(const Duration(days: 1));
    const white70 = TextStyle(color: Colors.white70, fontSize: AppTypography.s12);

    // ช่วงวันที่ใช้ไฟ/น้ำของรอบนี้ (ชิปซ้าย) + เดือนที่ออกใบแจ้งหนี้ (ขวา) —
    // บิลตั้งชื่อตามเดือนที่ปิดรอบ จึงบอกทั้งสองอย่าง จอแคบ/ตัวอักษรใหญ่จน
    // วางคู่กันไม่พอ เดือนบิลจะตกลงบรรทัดถัดไปแทนการล้นขอบ
    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  cycleReady
                      ? 'รอบ ${_shortDate(data.cycleStart)} – ${_shortDate(lastDay)}'
                      : 'รอบบิลนี้',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTypography.s12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (cycleReady)
          Text(
            'บิลเดือน ${thaiMonthsShort[cycleEnd.month - 1]} ${cycleEnd.year + 543}',
            style: white70,
          ),
      ],
    );

    final chip = onViewForecast == null ? null : _ForecastChip(onTap: onViewForecast!);

    // ยอดจริงที่ใช้ไปแล้ว (ข้อเท็จจริงจากเลขมิเตอร์) — ตัวเลขหลักของการ์ด
    // [trailing] วางชิดขวาบรรทัดเดียวกับตัวเลข บรรทัดที่มาของยอดจึงยาวได้เต็มแถว
    Widget amount({Widget? trailing}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ใช้ไปแล้วรอบนี้',
                style: TextStyle(color: Colors.white70, fontSize: AppTypography.s13, height: 1.3)),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AnimatedAmount(
                      value: usedSoFar,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppTypography.s32,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.3),
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
            // บอกที่มาของยอด — มีรายจ่ายประจำในเดือนบิลนี้ = บวกรวมไว้แล้ว
            const SizedBox(height: 2),
            Text(
              fixedCost > 0 ? 'ค่าไฟ + ค่าน้ำ · รวมรายจ่ายประจำแล้ว' : 'ค่าไฟ + ค่าน้ำ',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: white70,
            ),
          ],
        );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 18),
        amount(trailing: chip),
        const SizedBox(height: 18),
        _CycleBar(progress: cycleReady ? progress : 0),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                cycleReady
                    ? 'วันที่ ${daysElapsed + 1} จาก $cycleLengthDays วัน'
                    : 'ยังไม่ได้ตั้งวันตัดรอบบิล',
                style: white70,
              ),
            ),
            if (cycleReady)
              Text('เหลือ $remainingDays วัน',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTypography.s12,
                      fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryGreenLight, AppColors.primaryGreen],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        child: Stack(
          children: [
            // วงกลมโปร่งตกแต่ง 2 วง (ขวาบน/ซ้ายล่าง) ให้การ์ดมีมิติแบบนุ่มๆ
            Positioned(right: -50, top: -60, child: _glow(180, 0.07)),
            Positioned(left: -40, bottom: -70, child: _glow(150, 0.035)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: body,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _glow(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );
}

// แถบความคืบหน้าของรอบบิล (วันที่ผ่านไป ÷ ความยาวรอบ) เคลื่อนไปหาค่าใหม่แบบนุ่มๆ
class _CycleBar extends StatelessWidget {
  final double progress;

  const _CycleBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, p, _) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: p,
          minHeight: 8,
          backgroundColor: Colors.white.withValues(alpha: 0.18),
          valueColor: const AlwaysStoppedAnimation(Colors.white),
        ),
      ),
    );
  }
}

// ชิปเล็กใต้ยอดที่ใช้ไปแล้ว พาไปดูคาดการณ์สิ้นรอบบิลที่แท็บวิเคราะห์
class _ForecastChip extends StatelessWidget {
  final VoidCallback onTap;

  const _ForecastChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insights_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              const Flexible(
                child: Text('ดูคาดการณ์',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: AppTypography.s12,
                        fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: Colors.white.withValues(alpha: 0.85)),
            ],
          ),
        ),
      ),
    );
  }
}
