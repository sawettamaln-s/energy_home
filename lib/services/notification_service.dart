import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../models/notification_item_model.dart';

/// ===========================================================
/// NotificationService
/// รวมการจัดการ local notification ทั้งหมดของแอปไว้ที่เดียว
/// แบ่งเป็น 2 ประเภท:
/// 1) Scheduled  -> ตั้งเวลาล่วงหน้า ทำงานแม้ปิดแอป (OS เป็นคนสั่งเตือน)
///    ใช้กับ: เตือนใกล้วันตัดรอบบิล
/// 2) Instant    -> ยิงทันทีตอนแอปเปิด/บันทึกมิเตอร์แล้วตรวจพบเงื่อนไข
///    ใช้กับ: ยังไม่บันทึกมิเตอร์นาน, ใช้เกิน 30%, สรุปจบรอบบิล
///
/// ทุกครั้งที่ยิงแจ้งเตือนจริง (ไม่ใช่ตอน schedule) จะถูกบันทึกลง
/// "ประวัติ" ผ่าน SharedPreferences ด้วย เพื่อให้หน้า Notification
/// Center ดึงมาแสดงเป็นลิสต์ได้ (ตัว plugin เองไม่มี history ให้)
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

  // ----- key ที่เก็บ history ใน SharedPreferences -----
  static const String _historyKey = 'notification_history';

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
      // เผื่อหา timezone ไม่เจอในบางเครื่อง ใช้ค่าเริ่มต้นของเครื่องไปก่อน
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
  // ตัวกลางสำหรับ "ยิง notification จริง + บันทึกลง history" พร้อมกัน
  // ทุกเมธอด instant ด้านล่างเรียกผ่านตัวนี้ทั้งหมด เพื่อไม่ต้องเขียน
  // โค้ดบันทึก history ซ้ำทุกที่
  // =====================================================================
  Future<void> _showAndLog({
    required int pluginId,
    required String title,
    required String body,
    required String type,
  }) async {
    await _plugin.show(pluginId, title, body, _details());
    await _addToHistory(NotificationItem(
      id: const Uuid().v4(),
      title: title,
      body: body,
      type: type,
      timestamp: DateTime.now(),
    ));
  }

  // =====================================================================
  // (Scheduled) เตือนใกล้วันตัดรอบบิล
  // ใช้ zonedSchedule -> OS จะจัดการเตือนให้แม้ปิดแอปสนิท
  // หมายเหตุ: รายการนี้จะไม่ขึ้นใน history ทันที (ยังไม่ถูกยิงจริง)
  // จะถูกบันทึกก็ตอนที่ผู้ใช้เปิดแอปแล้วระบบ sync เข้า history ให้
  // (ดู syncDeliveredScheduledNotifications)
  // =====================================================================
  Future<void> scheduleBillingReminder({
    required DateTime billingDate,
    int daysBefore = 3,
  }) async {
    final reminderDate = billingDate.subtract(Duration(days: daysBefore));
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

    // เก็บ "กำหนดการ" ไว้เทียบเวลาตอนเปิดแอปครั้งถัดไป ว่าถึงเวลาที่ควร
    // ขึ้นใน history แล้วหรือยัง (ดูเมธอด syncDeliveredScheduledNotifications)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'pending_billing_reminder_time', scheduledTime.toIso8601String());
  }

  // เรียกตอนเปิดแอป (ทุกครั้งที่ _loadData ทำงาน) เพื่อเช็คว่า scheduled
  // notification ที่ตั้งไว้ "ถึงเวลาแล้ว" หรือยัง ถ้าถึงแล้วให้บันทึกเข้า
  // history เพื่อให้หน้า Notification Center เห็นรายการนี้ด้วย
  Future<void> syncDeliveredScheduledNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingStr = prefs.getString('pending_billing_reminder_time');
    if (pendingStr == null) return;

    final pendingTime = DateTime.tryParse(pendingStr);
    if (pendingTime == null) return;

    if (DateTime.now().isAfter(pendingTime)) {
      await _addToHistory(NotificationItem(
        id: const Uuid().v4(),
        title: 'ใกล้ถึงวันตัดรอบบิลแล้ว',
        body: 'ถึงกำหนดที่ตั้งเตือนไว้ก่อนวันตัดรอบบิล',
        type: 'billing',
        timestamp: pendingTime,
      ));
      await prefs.remove('pending_billing_reminder_time');
    }
  }

  // =====================================================================
  // (Instant) เตือนยังไม่บันทึกมิเตอร์เกิน N วัน
  // กันสแปม: เตือนได้สูงสุดวันละ 1 ครั้ง
  // =====================================================================
  Future<void> checkMeterNotRecorded({
    required DateTime? lastLogDate,
    int thresholdDays = 5,
  }) async {
    if (lastLogDate == null) return;
    final daysSince = DateTime.now().difference(lastLogDate).inDays;
    if (daysSince < thresholdDays) return;
    if (await _alreadyNotifiedToday('meter_reminder')) return;

    await _showAndLog(
      pluginId: idMeterReminder,
      title: 'ยังไม่ได้บันทึกมิเตอร์',
      body: 'ไม่ได้บันทึกค่ามิเตอร์มา $daysSince วันแล้ว ลองเปิดแอปบันทึกดูนะ',
      type: 'meter',
    );
    await _markNotifiedToday('meter_reminder');
  }

  // =====================================================================
  // (Instant) เตือนเมื่อใช้ไฟ/น้ำเกิน 30% ของเดือนก่อน
  // =====================================================================
  Future<void> checkUsageSpike({
    required double currentElectricityCost,
    required double lastMonthElectricityCost,
    required double currentWaterCost,
    required double lastMonthWaterCost,
    double thresholdPercent = 30,
  }) async {
    if (lastMonthElectricityCost > 0) {
      final percentChange = ((currentElectricityCost - lastMonthElectricityCost) /
              lastMonthElectricityCost) *
          100;
      if (percentChange >= thresholdPercent &&
          !await _alreadyNotifiedToday('spike_electricity')) {
        await _showAndLog(
          pluginId: idSpikeElectricity,
          title: 'ค่าไฟพุ่งขึ้น ⚡',
          body:
              'ค่าไฟเดือนนี้สูงกว่าเดือนก่อนแล้ว ${percentChange.toStringAsFixed(0)}% ลองเช็คการใช้งานดูนะ',
          type: 'spike',
        );
        await _markNotifiedToday('spike_electricity');
      }
    }

    if (lastMonthWaterCost > 0) {
      final percentChange =
          ((currentWaterCost - lastMonthWaterCost) / lastMonthWaterCost) * 100;
      if (percentChange >= thresholdPercent &&
          !await _alreadyNotifiedToday('spike_water')) {
        await _showAndLog(
          pluginId: idSpikeWater,
          title: 'ค่าน้ำพุ่งขึ้น 💧',
          body:
              'ค่าน้ำเดือนนี้สูงกว่าเดือนก่อนแล้ว ${percentChange.toStringAsFixed(0)}% ลองเช็คการใช้งานดูนะ',
          type: 'spike',
        );
        await _markNotifiedToday('spike_water');
      }
    }
  }

  // =====================================================================
  // (Instant) สรุปยอดเมื่อปิดรอบบิลเดือนปัจจุบันเสร็จ
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

    await _showAndLog(
      pluginId: idCycleSummary,
      title: 'สรุปบิลรอบที่ผ่านมา',
      body:
          'รอบบิลเดือน $month/$year ปิดแล้ว ยอดรวมทั้งสิ้น ฿${totalCost.toStringAsFixed(2)}',
      type: 'summary',
    );
    await prefs.setBool(key, true);
  }

  // =====================================================================
  // (Instant) แจ้งเตือนต้อนรับ — ยิงครั้งเดียวตอนสมัครบัญชี/ทำ Setup เสร็จ
  // เรียกจาก setup_screen.dart ตอนบัญชีใหม่ทำ setup เสร็จครั้งแรกเท่านั้น
  // (ไม่ใช่จาก Dashboard อีกต่อไป เพราะ Dashboard โหลดทุกครั้งที่ login
  // ไม่ใช่แค่ครั้งแรก) จุดเรียกนี้รันครั้งเดียวต่อบัญชีโดยธรรมชาติอยู่แล้ว
  // (ปุ่ม Save ใน setup_screen ถูก disable ระหว่างบันทึก กันกดซ้ำ และ
  // setup_screen จะไม่ถูกแสดงอีกเมื่อมี user doc อยู่แล้ว) จึงไม่ต้องมี
  // flag กันซ้ำแบบเดิมที่ผูกกับเครื่อง (SharedPreferences) ซึ่งผิดจุด
  // ประสงค์อยู่แล้ว (ผูกกับเครื่อง ไม่ใช่บัญชี)
  // =====================================================================
  Future<void> notifyWelcome() async {
    await _showAndLog(
      pluginId: idWelcome,
      title: 'ยินดีต้อนรับสู่ Energy Home 🏠',
      body: 'แอปจะช่วยติดตามค่าไฟ-น้ำให้ทุกวัน แตะเพื่อดูคู่มือเริ่มต้นใช้งาน',
      type: 'welcome',
    );
  }

  // =====================================================================
  // จัดการ "ประวัติแจ้งเตือน" สำหรับหน้า Notification Center
  // =====================================================================

  Future<void> _addToHistory(NotificationItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHistory();
    list.insert(0, item); // ใหม่สุดอยู่บนสุด
    // เก็บแค่ 100 รายการล่าสุด กันข้อมูลบวมไม่จำกัด
    final trimmed = list.length > 100 ? list.sublist(0, 100) : list;
    await prefs.setString(
      _historyKey,
      jsonEncode(trimmed.map((e) => e.toMap()).toList()),
    );
  }

  /// ดึงประวัติแจ้งเตือนทั้งหมด เรียงใหม่สุดมาก่อน
  Future<List<NotificationItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => NotificationItem.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// จำนวนแจ้งเตือนที่ยังไม่อ่าน (ใช้โชว์ badge ตัวเลขที่ปุ่มกระดิ่ง)
  Future<int> getUnreadCount() async {
    final list = await getHistory();
    return list.where((e) => !e.isRead).length;
  }

  /// กดอ่านรายการเดียว
  Future<void> markAsRead(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHistory();
    final updated =
        list.map((e) => e.id == id ? e.copyWith(isRead: true) : e).toList();
    await prefs.setString(
      _historyKey,
      jsonEncode(updated.map((e) => e.toMap()).toList()),
    );
  }

  /// กดอ่านทั้งหมด
  Future<void> markAllAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHistory();
    final updated = list.map((e) => e.copyWith(isRead: true)).toList();
    await prefs.setString(
      _historyKey,
      jsonEncode(updated.map((e) => e.toMap()).toList()),
    );
  }

  /// ลบรายการเดียว
  Future<void> deleteOne(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHistory();
    list.removeWhere((e) => e.id == id);
    await prefs.setString(
      _historyKey,
      jsonEncode(list.map((e) => e.toMap()).toList()),
    );
  }

  /// ลบทั้งหมด
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
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