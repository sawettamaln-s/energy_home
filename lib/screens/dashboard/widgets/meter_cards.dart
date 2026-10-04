import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../widgets/ui/animated_amount.dart';
import '../../../widgets/ui/app_card.dart';
import '../../../widgets/ui/icon_badge.dart';
import '../dashboard_styles.dart';
import '../record_meter_screen.dart';

// =====================================================================
// การ์ดไฟฟ้า/น้ำของรอบนี้ — เล่าเรื่องของประเภทนั้นจบในใบเดียว: ค่าใช้จ่าย
// ที่ใช้ไปแล้ว, ปริมาณที่ใช้, (TOU) สัดส่วน On-Peak, จดมิเตอร์ล่าสุดเมื่อไร
// และปุ่มไปหน้าเต็มจอ RecordMeterScreen (ดูเหตุผลที่แยกหน้าที่ต้นไฟล์
// record_meter_screen.dart) เลขมิเตอร์ดิบ (ล่าสุด/ต้นรอบ) ดูได้ในหน้าบันทึก
// =====================================================================
class MeterSummaryCard extends StatelessWidget {
  final MeterKind kind;
  final bool isTou; // ใช้เฉพาะ kind == electricity
  final double cost; // ค่าใช้จ่ายสะสมตั้งแต่ต้นรอบ
  final double units; // ปริมาณที่ใช้สะสมตั้งแต่ต้นรอบ
  // สัดส่วนหน่วย On-Peak (0–1) ของรอบนี้ — null = ไม่ใช่ TOU หรือยังไม่ได้จด
  final double? peakShare;
  // วันที่จดมิเตอร์ครั้งล่าสุดในรอบนี้ — null = รอบนี้ยังไม่ได้จด
  final DateTime? lastRecorded;
  final VoidCallback onRecord;

  const MeterSummaryCard({
    super.key,
    required this.kind,
    this.isTou = false,
    required this.cost,
    required this.units,
    this.peakShare,
    this.lastRecorded,
    required this.onRecord,
  });

  // "จดล่าสุด" แบบนับวันตามปฏิทิน (ไม่สนเวลา): วันนี้ / เมื่อวาน / n วันก่อน
  static String lastRecordedText(DateTime? date, DateTime now) {
    if (date == null) return 'รอบนี้ยังไม่ได้จด';
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (days <= 0) return 'จดล่าสุด วันนี้';
    if (days == 1) return 'จดล่าสุด เมื่อวาน';
    return 'จดล่าสุด $days วันก่อน';
  }

  @override
  Widget build(BuildContext context) {
    final isElectricity = kind == MeterKind.electricity;
    final accent = isElectricity
        ? DashboardStyles.electricityBorder
        : DashboardStyles.waterBorder;
    final unit = isElectricity ? 'หน่วย' : 'ลบ.ม.';
    final title = isElectricity ? (isTou ? 'ไฟฟ้า (TOU)' : 'ไฟฟ้า') : 'น้ำประปา';
    final icon = isElectricity ? Icons.bolt_rounded : Icons.water_drop_rounded;
    final caption =
        TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600);
    final share = peakShare;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: accent, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AppTypography.s14,
                        color: AppColors.textDark)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedAmount(
              value: cost,
              style: const TextStyle(
                  fontSize: AppTypography.s20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark),
            ),
          ),
          const SizedBox(height: 2),
          Text('ใช้ ${_format(units)} $unit', style: caption),
          if (share != null) ...[
            const SizedBox(height: 10),
            _PeakShareBar(share: share, color: accent),
          ],
          const Spacer(),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.schedule_rounded,
                  size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(lastRecordedText(lastRecorded, DateTime.now()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: caption),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRecord,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.12),
                foregroundColor: accent,
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('บันทึกมิเตอร์',
                  style: TextStyle(fontSize: AppTypography.s13)),
            ),
          ),
        ],
      ),
    );
  }
}

// ปริมาณ: คั่นหลักพัน ทศนิยมไม่เกิน 2 ตำแหน่ง (ไม่แสดง .00)
String _format(double v) => NumberFormat('#,##0.##').format(v);

// แถบสัดส่วน On-Peak (สีเข้ม) กับ Off-Peak (สีจาง) ของ TOU + ป้าย % On-Peak
// ใช้แถบกับตัวเลขตัวเดียวแทนหน่วยแยกสองช่วง การ์ดครึ่งจอจะได้ไม่แน่น
class _PeakShareBar extends StatelessWidget {
  final double share; // 0–1
  final Color color;

  const _PeakShareBar({required this.share, required this.color});

  @override
  Widget build(BuildContext context) {
    final peakFlex = (share * 1000).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (peakFlex > 0)
                  Expanded(flex: peakFlex, child: Container(color: color)),
                if (peakFlex < 1000)
                  Expanded(
                      flex: 1000 - peakFlex,
                      child: Container(color: color.withValues(alpha: 0.22))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('On-Peak ${(share * 100).round()}%',
            style: TextStyle(
                fontSize: AppTypography.s11,
                fontWeight: FontWeight.w600,
                color: color)),
      ],
    );
  }
}

// =====================================================================
// การ์ดล็อก — โชว์แทนการ์ดมิเตอร์ เฉพาะฝั่งที่ยังไม่พร้อมบันทึก (ยังไม่เคยตั้ง
// เลขต้นรอบ หรือเลขต้นรอบเป็นของรอบก่อน) ในขณะที่อีกฝั่งพร้อมแล้ว ไม่บล็อก
// ทั้งคู่ด้วยการ์ดเช็คลิสต์ เพราะฝั่งที่กรอกครบแล้วควรใช้งานได้เลย
// =====================================================================
class MeterLockedCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Color borderColor;
  // null = ยังไม่เคยตั้งค่าฝั่งนี้เลย, ไม่ null = เคยตั้งแล้วแต่รอบบิลเลื่อน
  // ไปแล้ว ต้องตั้งเลขต้นรอบใหม่ (DashboardData.staleCycleMessage)
  final String? message;
  final VoidCallback onSetStartMeter;

  const MeterLockedCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.borderColor,
    this.message,
    required this.onSetStartMeter,
  });

  @override
  Widget build(BuildContext context) {
    final isStaleCycle = message != null;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                  icon: Icons.lock_outline_rounded,
                  color: borderColor.withValues(alpha: 0.7),
                  size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AppTypography.s14,
                        color: Colors.grey.shade600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message ?? 'ยังไม่ได้ตั้งเลขมิเตอร์ต้นรอบฝั่งนี้',
            style: TextStyle(
                fontSize: AppTypography.s12,
                height: 1.45,
                color: Colors.grey.shade700),
          ),
          const Spacer(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSetStartMeter,
              style: OutlinedButton.styleFrom(
                foregroundColor: borderColor,
                side: BorderSide(color: borderColor.withValues(alpha: 0.5)),
                minimumSize: const Size(0, 42),
              ),
              icon: Icon(isStaleCycle ? Icons.refresh_rounded : Icons.add_rounded,
                  size: 18),
              label: Text(isStaleCycle ? 'ตั้งรอบใหม่' : 'ตั้งเลย',
                  style: const TextStyle(fontSize: AppTypography.s13)),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// แถบเตือนให้ตั้งวันตัดรอบบิล — ไม่บล็อกการใช้งานอะไร (ระบบยังใช้ค่าเริ่มต้น
// วันที่ 30 คำนวณได้อยู่) จึงเป็นแถบบางๆ สีจาง กดแล้วพาไปตั้งวันตัดรอบบิล
// =====================================================================
class BillingDayReminderBanner extends StatelessWidget {
  final VoidCallback onTap;

  const BillingDayReminderBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryGreen.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const IconBadge(
                  icon: Icons.event_repeat_rounded,
                  color: AppColors.primaryGreen,
                  size: 32),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'ยังไม่ได้ตั้งวันตัดรอบบิล แตะเพื่อตั้งค่า',
                  style: TextStyle(
                      fontSize: AppTypography.s13, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}
