import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// ===========================================================
/// NotificationService
/// รวมการจัดการ local notification ทั้งหมดของแอปไว้ที่เดียว
/// แบ่งเป็น 2 ประเภท:
/// 1) Scheduled  -> ตั้งเวลาล่วงหน้า ทำงานแม้ปิดแอป (OS เป็นคนสั่งเตือน)
///    ใช้กับ: เตือนใกล้วันตัดรอบบิล
/// 2) Instant    -> ยิงทันทีตอนแอปเปิด/บันทึกมิเตอร์แล้วตรวจพบเงื่อนไข
///    ใช้กับ: ยังไม่บันทึกมิเตอร์นาน, ใช้เกิน 30%, สรุปจบรอบบิล
///
/// ใช้ SharedPreferences เก็บ "วันที่เตือนล่าสุด" ของแต่ละประเภท
/// เพื่อกันไม่ให้ยิงเตือนซ้ำทุกครั้งที่เปิดแอป/รีเฟรชหน้า Dashboard
/// ===========================================================
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ----- Notification ID คงที่ของแต่ละประเภท (กันชนกัน) -----
  static const int idBillingReminder = 1001;
  static const int idMeterReminder = 1002;
  static const int idSpikeElectricity = 1003;
  static const int idSpikeWater = 1004;
  static const int idCycleSummary = 1005;
  static const int idWelcome = 1006;

  // ----- Channel สำหรับ Android -----
  static const String _channelId = 'energy_home_channel';
  static const String _channelName = 'การแจ้งเตือนพลังงานในบ้าน';
  static const String _channelDesc =
      'แจ้งเตือนเรื่องรอบบิล การบันทึกมิเตอร์ และการใช้พลังงานผิดปกติ';

  // =====================================================================
  // เรียกครั้งเดียวตอนเปิดแอป (เช่นใน main() ก่อน runApp)
  // ทำหน้าที่: เตรียม plugin, timezone, และสร้าง notification channel
  // =====================================================================
  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));
    } catch (_) {
      // เผื่อหา timezone ไม่เจอในบางเครื่อง ใช้ UTC offset เริ่มต้นไปก่อน
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    _initialized = true;
  }

  // ขอสิทธิ์แจ้งเตือน (Android 13+ ต้องขอ runtime, iOS ต้องขอเสมอ)
  // เรียกตอนเปิดแอปครั้งแรก หรือก่อนตั้ง notification ครั้งแรก
  Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  // =====================================================================
  // (Scheduled) เตือนใกล้วันตัดรอบบิล
  // พาร์ทนี้ทำหน้าที่: ตั้งแจ้งเตือนล่วงหน้า X วันก่อนถึงวันตัดรอบ
  // ใช้ zonedSchedule -> OS จะจัดการเตือนให้แม้ปิดแอปสนิท
  // =====================================================================
  Future<void> scheduleBillingReminder({
    required DateTime billingDate,
    int daysBefore = 3,
  }) async {
    final reminderDate = billingDate.subtract(Duration(days: daysBefore));
    // ถ้าวันที่เตือนผ่านมาแล้ว (เช่น เหลือน้อยกว่า daysBefore วัน) ไม่ต้องตั้ง
    if (reminderDate.isBefore(DateTime.now())) return;

    final scheduledTime = tz.TZDateTime(
      tz.local,
      reminderDate.year,
      reminderDate.month,
      reminderDate.day,
      9, // เตือนตอน 9 โมงเช้า
    );

    await _plugin.zonedSchedule(
      idBillingReminder,
      'ใกล้ถึงวันตัดรอบบิลแล้ว',
      'เหลืออีก $daysBefore วันจะตัดรอบบิล อย่าลืมตรวจสอบมิเตอร์ให้เรียบร้อย',
      scheduledTime,
      _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // =====================================================================
  // (Instant) เตือนยังไม่บันทึกมิเตอร์เกิน N วัน
  // เรียกตอนโหลดหน้า Dashboard เสร็จ เช็คจากวันที่ของ log ล่าสุด
  // กันสแปม: เตือนได้สูงสุดวันละ 1 ครั้ง (เก็บวันที่เตือนล่าสุดไว้)
  // =====================================================================
  Future<void> checkMeterNotRecorded({
    required DateTime? lastLogDate,
    int thresholdDays = 5,
  }) async {
    if (lastLogDate == null) return;
    final daysSince = DateTime.now().difference(lastLogDate).inDays;
    if (daysSince < thresholdDays) return;

    if (await _alreadyNotifiedToday('meter_reminder')) return;

    await _plugin.show(
      idMeterReminder,
      'ยังไม่ได้บันทึกมิเตอร์',
      'ไม่ได้บันทึกค่ามิเตอร์มา $daysSince วันแล้ว ลองเปิดแอปบันทึกดูนะ',
      _details(),
    );
    await _markNotifiedToday('meter_reminder');
  }

  // =====================================================================
  // (Instant) เตือนเมื่อใช้ไฟ/น้ำเกิน 30% ของเดือนก่อน
  // พาร์ทนี้ทำหน้าที่: เทียบยอดใช้ปัจจุบัน (เทียบสัดส่วนวันที่ผ่านมาในรอบ)
  // กับเดือนก่อน ถ้าสูงกว่า threshold% ให้เตือนทันที
  // เรียกหลังบันทึกมิเตอร์สำเร็จ หรือหลังโหลดข้อมูล Dashboard
  // =====================================================================
  Future<void> checkUsageSpike({
    required double currentElectricityCost,
    required double lastMonthElectricityCost,
    required double currentWaterCost,
    required double lastMonthWaterCost,
    double thresholdPercent = 30,
  }) async {
    // ไฟฟ้า
    if (lastMonthElectricityCost > 0) {
      final percentChange = ((currentElectricityCost - lastMonthElectricityCost) /
              lastMonthElectricityCost) *
          100;
      if (percentChange >= thresholdPercent &&
          !await _alreadyNotifiedToday('spike_electricity')) {
        await _plugin.show(
          idSpikeElectricity,
          'ค่าไฟพุ่งขึ้น ⚡',
          'ค่าไฟเดือนนี้สูงกว่าเดือนก่อนแล้ว ${percentChange.toStringAsFixed(0)}% ลองเช็คการใช้งานดูนะ',
          _details(),
        );
        await _markNotifiedToday('spike_electricity');
      }
    }

    // น้ำ
    if (lastMonthWaterCost > 0) {
      final percentChange =
          ((currentWaterCost - lastMonthWaterCost) / lastMonthWaterCost) * 100;
      if (percentChange >= thresholdPercent &&
          !await _alreadyNotifiedToday('spike_water')) {
        await _plugin.show(
          idSpikeWater,
          'ค่าน้ำพุ่งขึ้น 💧',
          'ค่าน้ำเดือนนี้สูงกว่าเดือนก่อนแล้ว ${percentChange.toStringAsFixed(0)}% ลองเช็คการใช้งานดูนะ',
          _details(),
        );
        await _markNotifiedToday('spike_water');
      }
    }
  }

  // =====================================================================
  // (Instant) สรุปยอดเมื่อปิดรอบบิลเดือนปัจจุบันเสร็จ
  // พาร์ทนี้ทำหน้าที่: เรียกตอนระบบเพิ่งสร้างบิลใหม่สำเร็จ (compileBill)
  // เพื่อบอกภาพรวมว่าจบรอบนี้ใช้ไป/จ่ายไปเท่าไหร่
  // กันแจ้งซ้ำด้วย billId เป็น key เฉพาะของบิลนั้น (ไม่ใช่ต่อวัน)
  // =====================================================================
  Future<void> notifyCycleSummary({
    required String billId,
    required double totalCost,
    required int year,
    required int month,
  }) async {
    final key = 'cycle_summary_$billId';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) ?? false) return;

    await _plugin.show(
      idCycleSummary,
      'สรุปบิลรอบที่ผ่านมา',
      'รอบบิลเดือน $month/$year ปิดแล้ว ยอดรวมทั้งสิ้น ฿${totalCost.toStringAsFixed(2)}',
      _details(),
    );
    await prefs.setBool(key, true);
  }

  // =====================================================================
  // (Instant) แจ้งเตือนต้อนรับ — ยิงครั้งเดียวตอนสมัครบัญชี/ทำ Setup เสร็จ
  // เรียกจากหน้าสุดท้ายของ Setup Wizard (หรือหลัง createUser สำเร็จ)
  // กันยิงซ้ำด้วย SharedPreferences flag 'welcome_notified'
  // =====================================================================
  Future<void> notifyWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('welcome_notified') ?? false) return;

    await _plugin.show(
      idWelcome,
      'ยินดีต้อนรับสู่ Energy Home 🏠',
      'แอปจะช่วยติดตามค่าไฟ-น้ำให้ทุกวัน แตะเพื่อดูคู่มือเริ่มต้นใช้งาน',
      _details(),
    );
    await prefs.setBool('welcome_notified', true);
  }

  // ----- helper กันแจ้งเตือนซ้ำในวันเดียวกัน (ต่อประเภท) -----
  Future<bool> _alreadyNotifiedToday(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final lastDateStr = prefs.getString('notif_${key}_date');
    if (lastDateStr == null) return false;
    final lastDate = DateTime.tryParse(lastDateStr);
    if (lastDate == null) return false;
    final now = DateTime.now();
    return lastDate.year == now.year &&
        lastDate.month == now.month &&
        lastDate.day == now.day;
  }

  Future<void> _markNotifiedToday(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_${key}_date', DateTime.now().toIso8601String());
  }
}