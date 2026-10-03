import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
///    ใช้กับ: เตือนเช้าวันตัดรอบบิล
/// 2) Instant    -> ยิงทันทีตอนแดชบอร์ดโหลดข้อมูล (เปิดแอป/ข้อมูลเปลี่ยน)
///    แล้วตรวจพบเงื่อนไข ใช้กับ: ยังไม่บันทึกมิเตอร์นาน, ค่าใช้จ่ายพุ่งขึ้น,
///    คาดการณ์สิ้นรอบสูงกว่าเดือนก่อน, สรุปจบรอบบิล, รอบบิลที่ไม่มีข้อมูล,
///    ต้อนรับบัญชีใหม่
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
  static const int idForecastHigher = 1007;
  static const int idMissedCycle = 1008;

  // ----- Channel สำหรับ Android -----
  static const String _channelId = 'energy_home_channel';
  static const String _channelName = 'การแจ้งเตือนพลังงานในบ้าน';
  static const String _channelDesc =
      'แจ้งเตือนเรื่องรอบบิล การบันทึกมิเตอร์ และการใช้พลังงานผิดปกติ';

  // ----- key ที่เก็บ history ใน SharedPreferences -----
  static const String _historyKey = 'notification_history';

  // =====================================================================
  // เปิด/ปิดแจ้งเตือนแยกตามประเภท — เก็บใน SharedPreferences ของเครื่อง
  // (แยกตามบัญชีที่ล็อกอิน) ไม่ sync ข้ามเครื่อง
  //
  // toggle ที่ผู้ใช้ตั้งได้:
  //   'billing' -> เตือนเช้าวันตัดรอบบิล
  //   'meter'   -> เตือนยังไม่บันทึกมิเตอร์ + รอบบิลที่ไม่มีข้อมูล
  //   'spike'   -> ค่าใช้จ่ายพุ่งขึ้น + คาดการณ์สิ้นรอบสูงกว่าเดือนก่อน
  //   'summary' -> สรุปยอดท้ายรอบบิล
  // (แจ้งเตือนต้อนรับยิงเสมอ ไม่มี toggle)
  // ค่าเริ่มต้นของทุกประเภทคือ "เปิด" (true) ถ้ายังไม่เคยตั้งค่าไว้
  static const List<String> notificationTypes = [
    'billing',
    'meter',
    'spike',
    'summary',
  ];

  String _prefKey(String type) => 'notif_pref_$type';

  Future<bool> isTypeEnabled(String type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scopedKey(_prefKey(type))) ?? true;
  }

  Future<void> setTypeEnabled(String type, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scopedKey(_prefKey(type)), enabled);
    // 'billing' ใช้ zonedSchedule ตั้งเตือนล่วงหน้าไว้กับ OS ถ้าปิด toggle
    // ต้องยกเลิกอันที่ตั้งไว้ค้างด้วย ไม่งั้นจะยิงออกมาทั้งที่ปิดไปแล้ว
    // (ประเภทอื่นเป็น instant ยิงตอนเช็คเงื่อนไขสดๆ ไม่ต้องยกเลิกอะไร)
    if (type == 'billing' && !enabled) {
      await _plugin.cancel(idBillingReminder);
      await prefs.remove(_scopedKey('pending_billing_reminder_time'));
    }
  }

  /// ดึงค่าทั้งหมดรวดเดียว ใช้ตอนแสดงผลหน้าตั้งค่า (กัน await วนหลายรอบ)
  Future<Map<String, bool>> getAllTypePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final type in notificationTypes)
        type: prefs.getBool(_scopedKey(_prefKey(type))) ?? true,
    };
  }

  // =====================================================================
  // ผูก key ทุกตัวที่เก็บใน SharedPreferences กับ uid ของบัญชีที่ login
  // อยู่ตอนนั้น เพื่อกันไม่ให้ถ้าเครื่องเดียวถูกใช้ login สลับกัน 2 บัญชี
  // ประวัติแจ้งเตือน/unread badge/สถานะกันยิงซ้ำของบัญชี A ไปปนกับบัญชี B
  // ถ้าไม่มี user login อยู่ (เคสที่ไม่ควรเกิดในทางปฏิบัติ) fallback ไปใช้
  // 'guest' กันแอป crash
  // =====================================================================
  // เปลี่ยนได้เฉพาะในเทส (กำหนด uid เองโดยไม่ต้องมี Firebase)
  @visibleForTesting
  String Function() uidProvider =
      () => FirebaseAuth.instance.currentUser?.uid ?? 'guest';

  String get _uid => uidProvider();
  String _scopedKey(String key) => '${_uid}_$key';

  // =====================================================================
  // เรียกครั้งเดียวตอนเปิดแอป (ใน main() ก่อน runApp)
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
    // silent = true: บันทึกลงประวัติ (โชว์ในหน้าแจ้งเตือน) แต่ไม่ยิง
    // push notification จริง — ใช้ตอนโหลด Dashboard ครั้งแรกหลังสมัคร
    // สมาชิกเสร็จ กันไม่ให้มี notification popup ขึ้นถี่เกินไปตั้งแต่
    // เพิ่งเข้าแอปครั้งแรก (ให้เห็นแค่ welcome message พอ ที่เหลือไปดูเอา
    // ในหน้าแจ้งเตือนได้)
    bool silent = false,
  }) async {
    if (!silent) {
      await _plugin.show(pluginId, title, body, _details());
    }
    await _addToHistory(NotificationItem(
      id: const Uuid().v4(),
      title: title,
      body: body,
      type: type,
      timestamp: DateTime.now(),
    ));
  }

  // =====================================================================
  // (Scheduled) เตือนเช้าวันตัดรอบบิล (09:00) ให้บันทึกเลขมิเตอร์จาก
  // ใบแจ้งหนี้ใบใหม่เพื่อเริ่มรอบบิลใหม่
  // ใช้ zonedSchedule -> OS จะจัดการเตือนให้แม้ปิดแอปสนิท ตั้งไว้ทีละครั้ง
  // (id เดียวกัน เขียนทับของเดิม) และตั้งใหม่ทุกครั้งที่แดชบอร์ดโหลด
  // หมายเหตุ: รายการนี้จะไม่ขึ้นใน history ทันที (ยังไม่ถูกยิงจริง)
  // จะถูกบันทึกก็ตอนที่ผู้ใช้เปิดแอปแล้วระบบ sync เข้า history ให้
  // (ดู syncDeliveredScheduledNotifications — ต้องเรียกก่อนเมธอดนี้)
  // =====================================================================
  static const String billingReminderTitle = 'ถึงวันตัดรอบบิลแล้วค่ะ';
  static const String billingReminderBody =
      'ได้ใบแจ้งหนี้ใบใหม่แล้ว อย่าลืมบันทึกเลขมิเตอร์จากใบแจ้งหนี้ '
      'เพื่อเริ่มรอบบิลใหม่นะคะ';

  // เวลาที่ควรเตือนครั้งถัดไป: 09:00 ของวันตัดรอบ — ถ้าวันนี้คือวันตัดรอบ
  // (cycleStart) และยังไม่ถึง 09:00 ใช้ของวันนี้ ไม่งั้นใช้วันตัดรอบครั้งถัดไป
  @visibleForTesting
  static DateTime billingReminderTime({
    required DateTime cycleStart,
    required DateTime cycleEnd,
    required DateTime now,
  }) {
    DateTime at9(DateTime d) => DateTime(d.year, d.month, d.day, 9);
    return now.isBefore(at9(cycleStart)) ? at9(cycleStart) : at9(cycleEnd);
  }

  Future<void> scheduleBillingReminder({
    required DateTime cycleStart,
    required DateTime cycleEnd,
  }) async {
    if (!await isTypeEnabled('billing')) return;

    final target = billingReminderTime(
        cycleStart: cycleStart, cycleEnd: cycleEnd, now: DateTime.now());
    final scheduledTime = tz.TZDateTime(
        tz.local, target.year, target.month, target.day, target.hour);

    await _plugin.zonedSchedule(
      idBillingReminder,
      billingReminderTitle,
      billingReminderBody,
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
        _scopedKey('pending_billing_reminder_time'),
        scheduledTime.toIso8601String());
  }

  // เรียกตอนเปิดแอป (ทุกครั้งที่ _loadData ทำงาน) เพื่อเช็คว่า scheduled
  // notification ที่ตั้งไว้ "ถึงเวลาแล้ว" หรือยัง ถ้าถึงแล้วให้บันทึกเข้า
  // history เพื่อให้หน้า Notification Center เห็นรายการนี้ด้วย
  // ต้องเรียกก่อน scheduleBillingReminder ไม่งั้นกำหนดการที่ส่งไปแล้วจะถูก
  // เขียนทับด้วยกำหนดการใหม่ก่อนได้บันทึกเข้า history
  Future<void> syncDeliveredScheduledNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scopedKey('pending_billing_reminder_time');
    final pendingStr = prefs.getString(key);
    if (pendingStr == null) return;

    final pendingTime = DateTime.tryParse(pendingStr);
    if (pendingTime == null) return;

    if (DateTime.now().isAfter(pendingTime)) {
      await _addToHistory(NotificationItem(
        id: const Uuid().v4(),
        title: billingReminderTitle,
        body: billingReminderBody,
        type: 'billing',
        timestamp: pendingTime,
      ));
      await prefs.remove(key);
    }
  }

  // =====================================================================
  // (Instant) เตือนยังไม่บันทึกมิเตอร์เกิน N วัน
  // นับจากเหตุการณ์ล่าสุดระหว่างบันทึกมิเตอร์ครั้งล่าสุด (lastLogDate) กับการตั้ง
  // เลขมิเตอร์ต้นรอบครั้งล่าสุด (startMeterSetAt) — ผู้ใช้ที่ตั้งเลขต้นรอบแล้ว
  // แต่ยังไม่เคยบันทึกเลยก็ได้รับเตือน และการตั้งเลขต้นรอบใหม่นับเป็นการบันทึก
  // กันสแปม: เตือนได้สูงสุดวันละ 1 ครั้ง
  // =====================================================================
  Future<void> checkMeterNotRecorded({
    required DateTime? lastLogDate,
    DateTime? startMeterSetAt,
    int thresholdDays = 5,
    bool silent = false,
  }) async {
    if (!await isTypeEnabled('meter')) return;
    final references = [lastLogDate, startMeterSetAt].whereType<DateTime>().toList();
    if (references.isEmpty) return;
    references.sort();
    final daysSince = DateTime.now().difference(references.last).inDays;
    if (daysSince < thresholdDays) return;
    if (await _alreadyNotifiedToday('meter_reminder')) return;

    // ยังไม่เคยบันทึกเลย (หรือบันทึกล่าสุดเก่ากว่าการตั้งเลขต้นรอบ) นับจากวันตั้ง
    // เลขต้นรอบ จึงบอกตามนั้น
    final fromStartMeter = lastLogDate == null ||
        (startMeterSetAt != null && startMeterSetAt.isAfter(lastLogDate));
    await _showAndLog(
      pluginId: idMeterReminder,
      title: 'ยังไม่ได้บันทึกมิเตอร์เลยค่ะ',
      body: fromStartMeter
          ? 'ตั้งเลขมิเตอร์ต้นรอบไว้ $daysSince วันแล้ว ยังไม่ได้บันทึกมิเตอร์เลยนะคะ '
              'ลองเปิดแอปบันทึกดูนะคะ'
          : 'คุณยังไม่ได้บันทึกค่ามิเตอร์มา $daysSince วันแล้วนะคะ ลองเปิดแอปบันทึกดูนะคะ',
      type: 'meter',
      silent: silent,
    );
    await _markNotifiedToday('meter_reminder');
  }

  // =====================================================================
  // (Instant) เตือนเมื่อค่าไฟ/ค่าน้ำที่ใช้ไปแล้วในรอบนี้ สูงกว่าบิลเดือนก่อน
  // ตั้งแต่ thresholdPercent (30%) ขึ้นไป — เตือนแยกไฟ/น้ำ รอบละครั้ง
  // =====================================================================
  Future<void> checkUsageSpike({
    required double currentElectricityCost,
    required double lastMonthElectricityCost,
    required double currentWaterCost,
    required double lastMonthWaterCost,
    required DateTime cycleStart,
    double thresholdPercent = 30,
    bool silent = false,
  }) async {
    if (!await isTypeEnabled('spike')) return;
    if (lastMonthElectricityCost > 0) {
      final percentChange =
          ((currentElectricityCost - lastMonthElectricityCost) /
                  lastMonthElectricityCost) *
              100;
      if (percentChange >= thresholdPercent &&
          !await _alreadyNotifiedThisCycle('spike_electricity', cycleStart)) {
        await _showAndLog(
          pluginId: idSpikeElectricity,
          title: 'ค่าไฟเดือนนี้สูงขึ้นค่ะ',
          body:
              'ค่าไฟเดือนนี้ของคุณสูงกว่าเดือนก่อน ${percentChange.toStringAsFixed(0)}% ลองดูรายละเอียดการใช้งานได้นะคะ',
          type: 'spike',
          silent: silent,
        );
        await _markNotifiedThisCycle('spike_electricity', cycleStart);
      }
    }

    if (lastMonthWaterCost > 0) {
      final percentChange =
          ((currentWaterCost - lastMonthWaterCost) / lastMonthWaterCost) * 100;
      if (percentChange >= thresholdPercent &&
          !await _alreadyNotifiedThisCycle('spike_water', cycleStart)) {
        await _showAndLog(
          pluginId: idSpikeWater,
          title: 'ค่าน้ำเดือนนี้สูงขึ้นค่ะ',
          body:
              'ค่าน้ำเดือนนี้ของคุณสูงกว่าเดือนก่อน ${percentChange.toStringAsFixed(0)}% ลองดูรายละเอียดการใช้งานได้นะคะ',
          type: 'spike',
          silent: silent,
        );
        await _markNotifiedThisCycle('spike_water', cycleStart);
      }
    }
  }

  // =====================================================================
  // (Instant) เตือนล่วงหน้าเมื่อ "ค่าคาดการณ์สิ้นรอบ" (อัตราเฉลี่ยต่อวัน)
  // สูงกว่ายอดไฟ+น้ำของบิลเดือนก่อนตั้งแต่ threshold% (15%) — ต่างจาก
  // checkUsageSpike ที่เช็คยอดที่เกิดไปแล้ว ตัวนี้เตือนก่อนบิลจะออกจริง
  // ใช้ toggle 'spike' แต่บันทึกในประวัติเป็นประเภท 'forecast'
  // =====================================================================
  Future<void> checkForecastHigherThanLastMonth({
    required double forecastTotal,
    required double lastMonthTotal,
    required DateTime cycleStart,
    double thresholdPercent = 15,
    bool silent = false,
  }) async {
    if (!await isTypeEnabled('spike')) return;
    if (lastMonthTotal <= 0) return;

    final percentChange =
        ((forecastTotal - lastMonthTotal) / lastMonthTotal) * 100;

    if (percentChange < thresholdPercent) return;
    if (await _alreadyNotifiedThisCycle('forecast_higher', cycleStart)) {
      return;
    }

    await _showAndLog(
      pluginId: idForecastHigher,
      title: 'แนวโน้มค่าใช้จ่ายรอบนี้สูงขึ้นค่ะ',
      body:
          'คาดว่าค่าไฟ+ค่าน้ำรอบบิลนี้จะสูงกว่าเดือนก่อนประมาณ ${percentChange.toStringAsFixed(0)}% '
          'ลองดูการใช้พลังงานตอนนี้เลยดีกว่าค่ะ',
      type: 'forecast',
      silent: silent,
    );
    await _markNotifiedThisCycle('forecast_higher', cycleStart);
  }

  // =====================================================================
  // (Instant) สรุปยอดเมื่อระบบปิดบิลรอบที่เพิ่งจบ
  // กันแจ้งซ้ำด้วย billId เป็น key เฉพาะของบิลนั้น (ไม่ใช่ต่อวัน)
  // =====================================================================
  Future<void> notifyCycleSummary({
    required String billId,
    required double totalCost,
    required int year,
    required int month,
    bool silent = false,
  }) async {
    if (!await isTypeEnabled('summary')) return;
    final key = _scopedKey('cycle_summary_$billId');
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) ?? false) return;

    await _showAndLog(
      pluginId: idCycleSummary,
      title: 'สรุปบิลรอบที่ผ่านมาค่ะ',
      body:
          'รอบบิลเดือน $month/$year ปิดแล้ว ยอดรวมทั้งสิ้น ${totalCost.toStringAsFixed(2)} บาท ค่ะ',
      type: 'summary',
      silent: silent,
    );
    await prefs.setBool(key, true);
  }

  // =====================================================================
  // เช็คว่ารอบบิลนี้เคยแจ้งไปแล้วว่า "ไม่มี log เลย" (ผ่าน notifyMissedCycles)
  // หรือยัง — dashboard_screen.dart ใช้ข้ามรอบนั้นตอนไล่ปิดบิลย้อนหลัง กัน
  // query+compileBill ซ้ำทุกครั้งที่เปิดแอป (รอบที่ปิดไปแล้วไม่มีทางมี log
  // เพิ่ม ถ้าผู้ใช้กรอกย้อนหลังที่หน้าประวัติบิล จะสร้างบิลเองโดยไม่ผ่าน
  // compileBill)
  // =====================================================================
  Future<bool> isCycleFlaggedMissing(String monthKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scopedKey('missed_cycle_$monthKey')) ?? false;
  }

  // =====================================================================
  // (Instant) แจ้งเตือนรอบบิลที่ "ขาดหาย" — ไม่มี log บันทึกเลยในรอบนั้น
  // เรียกจาก dashboard_screen.dart หลังไล่ backfill ย้อนหลังแล้วพบว่ามีบาง
  // รอบที่ไม่มีข้อมูลให้ compile จริงๆ (user ไม่ได้เปิดแอปหลายรอบบิลติดกัน)
  // dedup เป็นรายเดือน (ไม่ใช่ทั้งก้อน) เพื่อไม่ให้แจ้งซ้ำเดือนที่เคยแจ้งไปแล้ว
  // แต่ยังแจ้งเดือนใหม่ที่เพิ่งพบเพิ่มได้ ถ้ามาพบทีหลังอีกที
  // =====================================================================
  Future<void> notifyMissedCycles({
    required List<String> months, // format 'M/YYYY' เช่น '7/2026'
    bool silent = false,
  }) async {
    if (months.isEmpty) return;
    if (!await isTypeEnabled('meter')) return;

    final prefs = await SharedPreferences.getInstance();
    final notYetNotified = <String>[];
    for (final m in months) {
      final key = _scopedKey('missed_cycle_$m');
      if (!(prefs.getBool(key) ?? false)) {
        notYetNotified.add(m);
      }
    }
    if (notYetNotified.isEmpty) return;

    final label = notYetNotified.join(', ');
    await _showAndLog(
      pluginId: idMissedCycle,
      title: 'มีรอบบิลที่ไม่มีข้อมูลบันทึกค่ะ',
      body:
          'ช่วง $label ไม่มีการบันทึกมิเตอร์เลย ระบบเลยไม่สามารถสร้างบิลเดือน'
          'นั้นให้ได้ค่ะ แตะเพื่อไปเพิ่มย้อนหลังได้เลยถ้าจำค่ามิเตอร์ตอนนั้นได้',
      // type แยกจาก 'meter' เพื่อให้แตะรายการในหน้าแจ้งเตือนแล้วพาไปหน้า
      // "ประวัติบิล" (ดู _onTapItem ใน notification_screen.dart) — ใช้ toggle
      // เดียวกับ 'meter' เพราะเป็นเรื่องเดียวกันในมุมมองผู้ใช้
      type: 'missed_cycle',
      silent: silent,
    );
    for (final m in notYetNotified) {
      await prefs.setBool(_scopedKey('missed_cycle_$m'), true);
    }
  }

  // =====================================================================
  // (Instant) แจ้งเตือนต้อนรับ — ยิงครั้งเดียวตอนสมัครบัญชี/ทำ Setup เสร็จ
  // เรียกจาก setup_screen.dart ตอนบัญชีใหม่ทำ setup เสร็จครั้งแรกเท่านั้น
  // จุดเรียกนี้รันครั้งเดียวต่อบัญชีโดยธรรมชาติอยู่แล้ว (ปุ่ม Save ใน
  // setup_screen ถูก disable ระหว่างบันทึก กันกดซ้ำ และ setup_screen จะไม่
  // ถูกแสดงอีกเมื่อมี user doc อยู่แล้ว) จึงไม่ต้องมี flag กันซ้ำเพิ่ม
  // =====================================================================
  Future<void> notifyWelcome() async {
    await _showAndLog(
      pluginId: idWelcome,
      title: 'ยินดีต้อนรับสู่ Energy Home ค่ะ',
      body:
          'เริ่มต้นใช้งานได้เลยโดยตั้งเลขมิเตอร์ต้นรอบที่หน้าหลัก '
          'แล้วบันทึกมิเตอร์เป็นประจำเพื่อติดตามค่าไฟ-น้ำค่ะ',
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
      _scopedKey(_historyKey),
      jsonEncode(trimmed.map((e) => e.toMap()).toList()),
    );
  }

  /// ดึงประวัติแจ้งเตือนทั้งหมด เรียงใหม่สุดมาก่อน
  Future<List<NotificationItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey(_historyKey));
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
      _scopedKey(_historyKey),
      jsonEncode(updated.map((e) => e.toMap()).toList()),
    );
  }

  /// กดอ่านทั้งหมด
  Future<void> markAllAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHistory();
    final updated = list.map((e) => e.copyWith(isRead: true)).toList();
    await prefs.setString(
      _scopedKey(_historyKey),
      jsonEncode(updated.map((e) => e.toMap()).toList()),
    );
  }

  /// ลบรายการเดียว
  Future<void> deleteOne(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHistory();
    list.removeWhere((e) => e.id == id);
    await prefs.setString(
      _scopedKey(_historyKey),
      jsonEncode(list.map((e) => e.toMap()).toList()),
    );
  }

  /// ลบทั้งหมด
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scopedKey(_historyKey));
  }

  // ----- helper กันแจ้งเตือนซ้ำในวันเดียวกัน (ต่อประเภท) -----
  Future<bool> _alreadyNotifiedToday(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final lastDateStr = prefs.getString(_scopedKey('notif_${key}_date'));
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
    await prefs.setString(
        _scopedKey('notif_${key}_date'), DateTime.now().toIso8601String());
  }

  // ----- helper กันแจ้งเตือนซ้ำ "ต่อรอบบิล" (ไม่ใช่ต่อวัน) -----
  // ใช้กับแจ้งเตือนที่ถ้าเงื่อนไขยังคงจริงอยู่ทุกวัน (เช่นค่าไฟพุ่งขึ้น
  // ค้างอยู่แบบนั้นทั้งเดือน) ไม่อยากให้เตือนซ้ำทุกวันจนน่ารำคาญ — เตือน
  // แค่ครั้งเดียวพอต่อ 1 รอบบิล จนกว่าจะขึ้นรอบใหม่ค่อยเตือนได้อีกครั้ง
  Future<bool> _alreadyNotifiedThisCycle(
      String key, DateTime cycleStart) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCycleStr = prefs.getString(_scopedKey('notif_${key}_cycle'));
    if (lastCycleStr == null) return false;
    final lastCycle = DateTime.tryParse(lastCycleStr);
    if (lastCycle == null) return false;
    return lastCycle.year == cycleStart.year &&
        lastCycle.month == cycleStart.month &&
        lastCycle.day == cycleStart.day;
  }

  Future<void> _markNotifiedThisCycle(String key, DateTime cycleStart) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _scopedKey('notif_${key}_cycle'), cycleStart.toIso8601String());
  }
}