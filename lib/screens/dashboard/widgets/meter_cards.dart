import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../dashboard_styles.dart';
import '../record_meter_screen.dart';

// =====================================================================
// การ์ดสรุปมิเตอร์ (ไฟฟ้า/น้ำ) — ไม่มีช่องกรอกในการ์ด มีแค่โชว์ค่าล่าสุด/
// ต้นรอบ แล้วกดปุ่มเดียวพาไปหน้าเต็มจอ RecordMeterScreen (ดูเหตุผลที่แยก
// หน้าที่ต้นไฟล์ record_meter_screen.dart)
// ค่าล่าสุด = เลขที่บันทึกครั้งล่าสุดในรอบนี้ ถ้ายังไม่ได้บันทึก ผู้เรียกส่ง
// ค่าต้นรอบมาแทน
// =====================================================================
class MeterSummaryCard extends StatelessWidget {
  final MeterKind kind;
  final bool isTou; // ใช้เฉพาะ kind == electricity
  final double? lastValue; // มิเตอร์ปกติ/น้ำ
  final double? startValue; // มิเตอร์ปกติ/น้ำ
  final double? lastPeak; // TOU
  final double? lastOffPeak; // TOU
  final VoidCallback onRecord;

  const MeterSummaryCard({
    super.key,
    required this.kind,
    this.isTou = false,
    this.lastValue,
    this.startValue,
    this.lastPeak,
    this.lastOffPeak,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.##');
    final isElectricity = kind == MeterKind.electricity;
    final borderColor = isElectricity
        ? DashboardStyles.electricityBorder
        : DashboardStyles.waterBorder;
    final badgeBg = isElectricity
        ? DashboardStyles.electricityFieldBg
        : DashboardStyles.waterFieldBg;
    final unit = isElectricity ? 'หน่วย' : 'ลบ.ม.';
    final title = isElectricity ? (isTou ? 'ไฟฟ้า (TOU)' : 'ไฟฟ้า') : 'น้ำ';
    final icon = isElectricity ? Icons.bolt : Icons.water_drop;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: DashboardStyles.accentCard(borderColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration:
                    BoxDecoration(color: badgeBg, shape: BoxShape.circle),
                child: Icon(icon, color: borderColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: borderColor,
                        fontWeight: FontWeight.w600,
                        fontSize: AppTypography.s13_5),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isTou) ...[
            _TouMeterRow(label: 'On-Peak', value: lastPeak, formatter: formatter),
            const SizedBox(height: 6),
            _TouMeterRow(
                label: 'Off-Peak', value: lastOffPeak, formatter: formatter),
          ] else ...[
            if (lastValue != null)
              RichText(
                text: TextSpan(
                  style: const TextStyle(color: DashboardStyles.textDark),
                  children: [
                    TextSpan(
                        text: formatter.format(lastValue),
                        style: const TextStyle(
                            fontSize: AppTypography.s20,
                            fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: ' $unit',
                        style: TextStyle(
                            fontSize: AppTypography.s12,
                            color: Colors.grey.shade600)),
                  ],
                ),
              ),
            if (startValue != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.v2),
                child: Text('ต้นรอบ ${formatter.format(startValue)} $unit',
                    style: DashboardStyles.lastValueStyle),
              ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRecord,
              style: ElevatedButton.styleFrom(
                backgroundColor: badgeBg,
                foregroundColor: borderColor,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.v9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.v10)),
              ),
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('บันทึกมิเตอร์',
                  style: TextStyle(
                      fontSize: AppTypography.s12_5,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ป้าย On-Peak/Off-Peak ทางซ้าย ค่าล่าสุดทางขวา (ไม่โชว์ต้นรอบในแถวนี้)
// ไม่ใส่ overflow/maxLines บังคับตัด ปล่อยให้ Text ห่อเองตามพื้นที่จริง
// ถ้าฟอนต์ระบบถูกซูม/ปรับใหญ่ขึ้นจะยืดหยุ่นตามนั้น
class _TouMeterRow extends StatelessWidget {
  final String label;
  final double? value;
  final NumberFormat formatter;

  const _TouMeterRow({
    required this.label,
    required this.value,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
        const Spacer(),
        Flexible(
          child: Text(
            formatter.format(value ?? 0),
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: AppTypography.s15,
                fontWeight: FontWeight.w600,
                color: DashboardStyles.textDark),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// การ์ดล็อก — โชว์แทนการ์ดสรุปมิเตอร์ เฉพาะฝั่งที่ยังไม่พร้อมบันทึก (ยังไม่
// เคยตั้งเลขต้นรอบ หรือเลขต้นรอบเป็นของรอบก่อน) ในขณะที่อีกฝั่งพร้อมแล้ว ไม่
// บล็อกทั้งคู่ด้วยการ์ดเช็คลิสต์ เพราะฝั่งที่กรอกครบแล้วควรใช้งานได้เลย ขนาด/
// โครงใกล้เคียง MeterSummaryCard ให้สูงเท่ากันตอนอยู่ใน Row เดียวกัน
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration:
          DashboardStyles.accentCard(borderColor.withValues(alpha: 0.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent.withValues(alpha: 0.5), size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: accent.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                  fontSize: AppTypography.s14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message ?? 'ยังไม่ได้ตั้งเลขมิเตอร์ต้นรอบฝั่งนี้',
            style: TextStyle(
                fontSize: AppTypography.s11_5, color: Colors.grey.shade600),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSetStartMeter,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.v10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.v10),
                ),
              ),
              icon: Icon(isStaleCycle ? Icons.refresh : Icons.add, size: 16),
              label: Text(isStaleCycle ? 'ตั้งรอบใหม่' : 'ตั้งเลย',
                  style: const TextStyle(fontSize: AppTypography.s12_5)),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// แบนเนอร์เล็กเตือนให้ตั้งวันตัดรอบบิล — ต่างจากการ์ดเช็คลิสต์ตรงที่ไม่บล็อก
// การใช้งานอะไรเลย (ระบบยังใช้ default 30 คำนวณให้ได้อยู่) จึงออกแบบให้เด่น
// น้อยกว่า เป็นแถบบางๆ กดแล้วพาไปตั้งวันตัดรอบบิล
// =====================================================================
class BillingDayReminderBanner extends StatelessWidget {
  final VoidCallback onTap;

  const BillingDayReminderBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.v12),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.v14, vertical: AppSpacing.v12),
        decoration: BoxDecoration(
          color: DashboardStyles.primaryGreen.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppSpacing.v12),
          border: Border.all(
              color: DashboardStyles.primaryGreen.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_repeat,
                color: DashboardStyles.primaryGreen, size: 19),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'ยังไม่ได้ตั้งวันตัดรอบบิล แตะเพื่อตั้งค่า',
                style: TextStyle(
                    fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 13, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}
