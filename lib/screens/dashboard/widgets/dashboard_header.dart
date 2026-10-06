import 'package:flutter/material.dart';

import '../../../models/user_model.dart';
import '../../../utils/thai_date_utils.dart';
import '../../../widgets/ui/app_card.dart';
import '../dashboard_styles.dart';

// =====================================================================
// Header ส่วนบนของหน้าหลัก: วันที่วันนี้ + คำทักทายตามช่วงเวลา + ปุ่มแจ้งเตือน
// (สถานะรอบบิลอยู่ในวงแหวนของการ์ดสรุปบิลด้านล่าง)
// =====================================================================
class DashboardHeader extends StatelessWidget {
  final UserModel? user;
  final int unreadNotifications; // badge ที่ปุ่มกระดิ่ง
  final VoidCallback onNotificationTap;

  const DashboardHeader({
    super.key,
    required this.user,
    required this.unreadNotifications,
    required this.onNotificationTap,
  });

  // ทักทายตามช่วงเวลาปัจจุบัน แทนคำว่า "สวัสดี" คงที่ตลอดวัน
  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'สวัสดีตอนเช้า';
    if (now.hour < 17) return 'สวัสดีตอนบ่าย';
    return 'สวัสดีตอนเย็น';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final name = (user?.name.isNotEmpty ?? false) ? user!.name : 'ผู้ใช้';

    return Row(
      children: [
        // Avatar ตัวอักษรแรกของชื่อ บนวงกลมขาวลอย (คู่กับปุ่มกระดิ่งฝั่งขวา)
        // ด้านในเป็นวงเขียวอ่อน ตัวอักษรสีเขียวหลัก
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: AppCard.softShadow,
          ),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryGreen.withValues(alpha: 0.10),
            ),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.w700,
                fontSize: AppTypography.s17,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${now.day} ${thaiMonths[now.month - 1]} ${now.year + 543}',
                style: TextStyle(
                    fontSize: AppTypography.s12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 1),
              Text(
                '${_greeting(now)}, $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.s18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _NotificationButton(
          unread: unreadNotifications,
          onTap: onNotificationTap,
        ),
      ],
    );
  }
}

// ปุ่มกระดิ่งในวงกลมขาวลอย พร้อม badge จำนวนที่ยังไม่อ่าน
class _NotificationButton extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;

  const _NotificationButton({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: AppCard.softShadow,
          ),
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.notifications_none_rounded,
                    color: AppColors.textDark),
              ),
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.spikeUp,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTypography.s9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
