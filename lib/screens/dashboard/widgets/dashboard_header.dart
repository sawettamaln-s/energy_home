import 'package:flutter/material.dart';

import '../../../models/user_model.dart';
import '../dashboard_styles.dart';

// =====================================================================
// Header ส่วนบนของหน้าหลัก: ชื่อผู้ใช้ทักทาย + สถานะรอบบิล + ปุ่มแจ้งเตือน
// บอกว่าอยู่ตรงไหนของรอบบิลปัจจุบัน (ผ่านมากี่วัน / เหลืออีกกี่วันก่อนปิดรอบ)
// =====================================================================
class DashboardHeader extends StatelessWidget {
  final UserModel? user;
  final int daysElapsed;
  final int remainingDays;
  final int cycleLengthDays;
  final int unreadNotifications; // badge ที่ปุ่มกระดิ่ง
  final VoidCallback onNotificationTap;

  const DashboardHeader({
    super.key,
    required this.user,
    required this.daysElapsed,
    required this.remainingDays,
    required this.cycleLengthDays,
    required this.unreadNotifications,
    required this.onNotificationTap,
  });

  // ทักทายตามช่วงเวลาปัจจุบัน แทนคำว่า "สวัสดี" คงที่ตลอดวัน
  String _greetingText() {
    final hour = DateTime.now().hour;
    final name = user?.name ?? 'ผู้ใช้';
    final period = hour < 12
        ? 'สวัสดีตอนเช้า'
        : hour < 17
            ? 'สวัสดีตอนบ่าย'
            : 'สวัสดีตอนเย็น';
    return '$period, $name';
  }

  @override
  Widget build(BuildContext context) {
    final progress = cycleLengthDays > 0
        ? (daysElapsed / cycleLengthDays).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar กลมเล็ก ๆ ให้ header ดูมีมิติ ไม่ใช่แค่ตัวอักษรลอย ๆ
        CircleAvatar(
          radius: 22,
          backgroundColor: DashboardStyles.primaryGreen.withValues(alpha: 0.12),
          child: Text(
            ((user?.name.isNotEmpty ?? false) ? user!.name.substring(0, 1) : 'U')
                .toUpperCase(),
            style: const TextStyle(
              color: DashboardStyles.primaryGreen,
              fontWeight: FontWeight.bold,
              fontSize: AppTypography.s18,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greetingText(), style: DashboardStyles.greeting),
              const SizedBox(height: 5),
              // ผู้ใช้ใหม่ที่ยังไม่ได้ตั้งวันตัดรอบบิล ยังไม่มี "รอบบิล"
              // ให้อ้างอิงจริง ๆ (billingDay ที่ใช้คำนวณ progress ตอนนี้
              // เป็นแค่ default = 30 ไปก่อน) โชว์ป้ายสถานะบัญชีแทนแถบ
              // ผ่านมา/เหลืออีก + progress bar ที่ยังไม่มีความหมายจนกว่า
              // จะตั้งค่าจริง
              if (user?.billingDayConfigured == false)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.v8, vertical: AppSpacing.v3),
                  decoration: BoxDecoration(
                    color: DashboardStyles.primaryGreen.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppSpacing.v20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('บัญชีใหม่', style: DashboardStyles.subGreeting),
                      Text(' • ', style: DashboardStyles.subGreeting),
                      Text('รอดำเนินการเปิดระบบคาดการณ์',
                          style: DashboardStyles.subGreeting),
                    ],
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.v8, vertical: AppSpacing.v3),
                  decoration: BoxDecoration(
                    color: DashboardStyles.primaryGreen.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppSpacing.v20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('ผ่านมา $daysElapsed วัน',
                          style: DashboardStyles.subGreeting),
                      const Text(' • ', style: DashboardStyles.subGreeting),
                      Text('เหลืออีก $remainingDays วัน',
                          style: DashboardStyles.subGreeting),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // แถบความคืบหน้าของรอบบิล (บาง ๆ ใต้ข้อความ)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.v4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.grey.shade200,
                    color: DashboardStyles.primaryGreen,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        // ปุ่มแจ้งเตือน -> หน้า Notification Center พร้อม badge จำนวนที่ยังไม่อ่าน
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded,
                  color: DashboardStyles.textDark),
              if (unreadNotifications > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.v4, vertical: AppSpacing.v1),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: const BoxDecoration(
                      color: AppColors.spikeUp,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unreadNotifications > 9 ? '9+' : '$unreadNotifications',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppTypography.s9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onPressed: onNotificationTap,
        ),
      ],
    );
  }
}
