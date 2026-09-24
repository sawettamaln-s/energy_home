// tool/forecast_synth/generate_household.dart
//
// สร้างข้อมูลจำลองบัญชีทดสอบ/เดโม "จากศูนย์" (ไม่ต้องมี CSV ต้นทาง) แล้ว
// ยัดลง Firestore ให้ครบทุกส่วนที่ธีสิสต้องใช้โชว์:
//   1) บิลย้อนหลัง 3 ปีถึงเดือนปัจจุบัน (คำนวณจากการใช้ไฟจริงของ "อุปกรณ์"
//      สมมติในบ้าน ไม่ใช่สุ่มเลขลอยๆ) — บางเดือนข้ามได้ตาม --skip-rate
//   2) ประวัติกรอกมิเตอร์รายเดือน อย่างน้อย 4-5 ครั้ง/เดือน (~รายสัปดาห์)
//   3) รายการอุปกรณ์ไฟฟ้าในบ้าน (แอร์ 2-3 ตัว + เครื่องใช้ไฟฟ้าทั่วไป) ที่
//      สอดคล้องกับตัวเลขการใช้ไฟที่คำนวณ (เขียนลง users/{uid}/appliances
//      ตรงกับ ApplianceModel ในแอป)
//   4) ตั้งวันตัดรอบบิล + meterType/area + เลขมิเตอร์ต้นรอบถัดไป
//
// โมเดลการคำนวณไฟ (bottom-up จากอุปกรณ์):
//   สำหรับแต่ละอุปกรณ์: กำลังไฟ(kW) x ชั่วโมงใช้งาน/สัปดาห์ x 4.348 สัปดาห์/
//   เดือน x duty factor (เฉพาะแอร์ กันประเมินสูงเกินจริงจากการตัดต่อ
//   thermostat) x seasonal multiplier (เฉพาะแอร์ อิงฤดูกาลไทย: ร้อน มี.ค.-
//   พ.ค. / ฝน มิ.ย.-ต.ค. / หนาว พ.ย.-ก.พ.) แล้วรวมทุกอุปกรณ์ + คูณ noise
//   สุ่มรายเดือน ±15% (seed ตายตัว) + trend เติบโตเบาๆ 3%/ปี
//   TOU: แต่ละอุปกรณ์มี peakFraction (สัดส่วนชั่วโมงใช้งานที่ตกช่วง On-Peak
//   จ-ศ 09:00-22:00) ที่ประเมินจากพฤติกรรมใช้งานจริงของอุปกรณ์นั้นๆ (เช่น
//   แอร์นอนกลางคืน = off-peak เกือบหมด, หม้อหุงข้าวมื้อเย็นวันธรรมดา = ส่วน
//   ใหญ่ on-peak)
//   น้ำ: baseline คงที่ต่อเดือน + ผันตามฤดูกาลเล็กน้อย (ร้อนอาบน้ำบ่อยขึ้น)
//
// วิธีใช้ (dry-run ก่อนเสมอ แล้วค่อย --apply):
//
//   dart run tool/forecast_synth/generate_household.dart \
//     --case=bangkok_normal \
//     --project-id=YOUR_PROJECT_ID \
//     --api-key=YOUR_FIREBASE_WEB_API_KEY \
//     --email=case1@gmail.com \
//     --billing-day=30
//
//   --case ที่รองรับ: bangkok_normal, bangkok_tou, upcountry_normal, upcountry_tou
//   ตัวเลือกเสริม: --skip-rate=0.12 (สัดส่วนเดือนที่ "ลืมออกบิล" สุ่มข้าม,
//   default 0 = ครบทุกเดือน) --months=36 (ค่า default 3 ปี) --readings-min=4
//   --readings-max=5 (default อยู่แล้วตามที่ต้องการ) --elec-start / --water-start

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _identityToolkitUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';

void main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) return;

  stdout.writeln(
      '=== Generate household (${options.caseName}, ${options.apply ? "APPLY" : "DRY-RUN"} mode) ===');

  final now = DateTime.now();

  // เดือนล่าสุดที่ "ปิดรอบแล้วจริง" ต้องดูวันตัดรอบด้วย ไม่ใช่แค่เดือนปฏิทิน
  // ปัจจุบัน — ถ้าวันนี้ยังไม่ถึงวันตัดรอบของเดือนนี้ (เช่น วันนี้ 24 แต่
  // billingDay=30) แปลว่าเดือนนี้ยังไม่ปิดรอบ เดือนล่าสุดที่ปิดจริงคือเดือน
  // ก่อนหน้า ถ้าสร้างบิล/ยอดปิดรอบของเดือนปัจจุบันไปทั้งที่ยังไม่ถึงวันตัด
  // รอบ จะทำให้ startBillingMonth/Year ที่ตั้งไว้ "ล้ำหน้า" กว่าวันจริง
  // (บอกแอปว่าอยู่รอบเดือนหน้าทั้งที่ปฏิทินจริงยังอยู่รอบเดือนนี้) ทำให้แอป
  // สับสนขึ้นเตือนให้ตั้งรอบใหม่ซ้ำๆ และ forecast เพี้ยน
  var endYear = now.year;
  var endMonth = now.month;
  if (now.day < options.billingDay) {
    endMonth -= 1;
    if (endMonth < 1) {
      endMonth = 12;
      endYear -= 1;
    }
  }

  var startMonth = endMonth;
  var startYear = endYear;
  for (var i = 0; i < options.months - 1; i++) {
    startMonth -= 1;
    if (startMonth < 1) {
      startMonth = 12;
      startYear -= 1;
    }
  }

  final appliances = _buildAppliances(options.isUpcountry);
  final months = <_MonthPlan>[];
  {
    var y = startYear, m = startMonth;
    for (var i = 0; i < options.months; i++) {
      months.add(_computeMonth(
          y, m, i, appliances, options.isTou, options.isUpcountry));
      m += 1;
      if (m > 12) {
        m = 1;
        y += 1;
      }
    }
  }

  stdout.writeln(
      'สร้างข้อมูล ${months.length} เดือน (${months.first.year}-${months.first.month.toString().padLeft(2, '0')} '
      'ถึง ${months.last.year}-${months.last.month.toString().padLeft(2, '0')}) '
      'สำหรับ ${options.isUpcountry ? "ตจว." : "กทม."} '
      'มิเตอร์${options.isTou ? "TOU" : "ปกติ"}\n');

  final client = HttpClient();
  try {
    stdout.writeln('กำลัง sign-in ด้วย ${options.email} ...');
    final auth = await _signIn(
      client: client,
      apiKey: options.apiKey,
      email: options.email,
      password: options.password,
    );
    final idToken = auth['idToken'] as String;
    final signedInUid = auth['localId'] as String;
    final targetUid = options.uid ?? signedInUid;
    stdout.writeln('sign-in สำเร็จ (signed-in uid: $signedInUid)\n');

    final firestore = _FirestoreRestClient(
      client: client,
      projectId: options.projectId,
      idToken: idToken,
    );

    final ftRate = await _getFtRate(firestore);
    stdout.writeln('Ft rate ที่ใช้คำนวณ: $ftRate\n');

    // ---------- คำนวณบิล (เว้นบางเดือนตาม --skip-rate) ----------
    final bills = <Map<String, dynamic>>[];
    var skippedCount = 0;
    for (final mp in months) {
      final skip =
          Random(mp.year * 131 + mp.month * 977).nextDouble() < options.skipRate;
      if (skip) {
        skippedCount++;
        continue;
      }
      final monthId =
          'imported_${mp.year}_${mp.month.toString().padLeft(2, '0')}';
      double electricityCost;
      double elecUsed = 0, peakUsed = 0, offPeakUsed = 0;
      if (options.isTou) {
        peakUsed = mp.peakKwh;
        offPeakUsed = mp.offPeakKwh;
        elecUsed = peakUsed + offPeakUsed;
        electricityCost = _calculateElectricityTOU(
            peakUnits: peakUsed, offPeakUnits: offPeakUsed, ftRate: ftRate);
      } else {
        elecUsed = mp.totalKwh;
        electricityCost =
            _calculateElectricity(elecUsed, options.area, ftRate);
      }
      final waterCost = options.area == 'bangkok'
          ? _calculateWaterMWA(mp.waterUnits)
          : _calculateWaterPWA(mp.waterUnits);
      final totalCost = electricityCost + waterCost;
      bills.add({
        'id': monthId,
        'uid': targetUid,
        'year': mp.year,
        'month': mp.month,
        'yearMonth': mp.year * 100 + mp.month,
        'electricityUsed': elecUsed,
        'electricityPeakUsed': peakUsed,
        'electricityOffPeakUsed': offPeakUsed,
        'waterUsed': mp.waterUnits,
        'electricityCost': electricityCost,
        'waterCost': waterCost,
        'fixedCost': 0.0,
        'totalCost': totalCost,
        'forecastElectricity': electricityCost,
        'forecastWater': waterCost,
        'forecastTotal': totalCost,
        'source': 'imported',
      });
    }
    stdout.writeln(
        'บิล: ${bills.length} เดือน (ข้าม $skippedCount เดือนตาม --skip-rate=${options.skipRate})\n');

    // ---------- คำนวณ log กรอกมิเตอร์ (หลายครั้ง/เดือน) + start_meter_history ----------
    final electricityLogs = <Map<String, dynamic>>[];
    final waterLogs = <Map<String, dynamic>>[];
    final startMeterRecords = <Map<String, dynamic>>[];

    double elecCumulative = options.elecStart;
    double peakCumulative = options.elecStart;
    double offPeakCumulative = 0;
    double waterCumulative = options.waterStart;

    DateTime previousCutoff = () {
      var prevMonth = months.first.month - 1;
      var prevYear = months.first.year;
      if (prevMonth < 1) {
        prevMonth = 12;
        prevYear -= 1;
      }
      return _safeBillingDate(prevYear, prevMonth, options.billingDay);
    }();

    for (final mp in months) {
      final cycleCutoff =
          _safeBillingDate(mp.year, mp.month, options.billingDay);
      final cycleStart = previousCutoff.add(const Duration(days: 1));
      final monthId =
          'imported_${mp.year}_${mp.month.toString().padLeft(2, '0')}';

      startMeterRecords.add({
        'id': monthId,
        'uid': targetUid,
        'electricityValue': options.isTou ? 0.0 : elecCumulative,
        'waterValue': waterCumulative,
        'peakValue': options.isTou ? peakCumulative : 0.0,
        'offPeakValue': options.isTou ? offPeakCumulative : 0.0,
        'billingMonth': mp.month,
        'billingYear': mp.year,
        'recordedAt': cycleStart.toIso8601String(),
      });

      final seed = mp.year * 100 + mp.month;
      final readingCount = options.readingsMin == options.readingsMax
          ? options.readingsMin
          : options.readingsMin +
              Random(seed).nextInt(
                  options.readingsMax - options.readingsMin + 1);

      final dates = _splitDatesAscending(
          cycleStart, cycleCutoff, readingCount, Random(seed * 7 + 1));
      final elecFractions =
          _splitIncreasingFractions(readingCount, Random(seed * 7 + 2));
      final peakFractions =
          _splitIncreasingFractions(readingCount, Random(seed * 7 + 3));
      final offPeakFractions =
          _splitIncreasingFractions(readingCount, Random(seed * 7 + 4));
      final waterFractions =
          _splitIncreasingFractions(readingCount, Random(seed * 7 + 5));

      double prevElecUsed = 0, prevPeakUsed = 0, prevOffPeakUsed = 0;
      double prevWaterUsed = 0;

      for (var i = 0; i < readingCount; i++) {
        final id = readingCount == 1 ? monthId : '${monthId}_${i + 1}';
        final date = dates[i];
        final isLast = i == readingCount - 1;

        double elecCost;
        double peakMeterValue = 0, offPeakMeterValue = 0, elecMeterValue = 0;
        double usedFromStartElec, usedFromLastElec;
        if (options.isTou) {
          final peakUsed =
              isLast ? mp.peakKwh : mp.peakKwh * peakFractions[i];
          final offPeakUsed =
              isLast ? mp.offPeakKwh : mp.offPeakKwh * offPeakFractions[i];
          peakCumulative = peakCumulative - prevPeakUsed + peakUsed;
          peakMeterValue = peakCumulative;
          offPeakCumulative =
              offPeakCumulative - prevOffPeakUsed + offPeakUsed;
          offPeakMeterValue = offPeakCumulative;
          usedFromStartElec = peakUsed + offPeakUsed;
          usedFromLastElec =
              (peakUsed - prevPeakUsed) + (offPeakUsed - prevOffPeakUsed);
          elecCost = _calculateElectricityTOU(
              peakUnits: peakUsed, offPeakUnits: offPeakUsed, ftRate: ftRate);
          prevPeakUsed = peakUsed;
          prevOffPeakUsed = offPeakUsed;
        } else {
          final elecUsed =
              isLast ? mp.totalKwh : mp.totalKwh * elecFractions[i];
          elecCumulative = elecCumulative - prevElecUsed + elecUsed;
          elecMeterValue = elecCumulative;
          usedFromStartElec = elecUsed;
          usedFromLastElec = elecUsed - prevElecUsed;
          elecCost = _calculateElectricity(elecUsed, options.area, ftRate);
          prevElecUsed = elecUsed;
        }
        electricityLogs.add({
          'id': id,
          'uid': targetUid,
          'date': date.toIso8601String(),
          'meterValue': elecMeterValue,
          'peakMeterValue': options.isTou ? peakMeterValue : null,
          'offPeakMeterValue': options.isTou ? offPeakMeterValue : null,
          'usedFromStart': usedFromStartElec,
          'usedFromLast': usedFromLastElec,
          'cost': elecCost,
        });

        final waterUsed =
            isLast ? mp.waterUnits : mp.waterUnits * waterFractions[i];
        waterCumulative = waterCumulative - prevWaterUsed + waterUsed;
        final waterCost = options.area == 'bangkok'
            ? _calculateWaterMWA(waterUsed)
            : _calculateWaterPWA(waterUsed);
        waterLogs.add({
          'id': id,
          'uid': targetUid,
          'date': date.toIso8601String(),
          'meterValue': waterCumulative,
          'usedFromStart': waterUsed,
          'usedFromLast': waterUsed - prevWaterUsed,
          'cost': waterCost,
        });
        prevWaterUsed = waterUsed;
      }

      previousCutoff = cycleCutoff;
    }

    // ---------- อุปกรณ์ไฟฟ้าในบ้าน ----------
    final applianceDocs = <Map<String, dynamic>>[];
    for (var i = 0; i < appliances.length; i++) {
      final a = appliances[i];
      applianceDocs.add({
        'id': 'imported_appliance_${i + 1}',
        'uid': targetUid,
        'name': a.name,
        'watt': a.watt,
        'schedules': a.scheduleBlocks
            .map((b) => {
                  'days': b.days,
                  'startTime': '00:00',
                  'endTime': _hoursToTimeString(b.hoursPerDay),
                })
            .toList(),
      });
    }

    // ---------- user doc update ----------
    final lastMonth = months.last;
    var nextMonth = lastMonth.month + 1;
    var nextYear = lastMonth.year;
    if (nextMonth > 12) {
      nextMonth = 1;
      nextYear += 1;
    }
    final userUpdate = <String, dynamic>{
      'billingDay': options.billingDay,
      'billingDayConfigured': true,
      'meterType': options.isTou ? 'tou' : 'normal',
      'area': options.area,
      'startElectricityValue': options.isTou ? 0.0 : elecCumulative,
      'startWaterValue': waterCumulative,
      'startPeakValue': options.isTou ? peakCumulative : 0.0,
      'startOffPeakValue': options.isTou ? offPeakCumulative : 0.0,
      'startBillingMonth': nextMonth,
      'startBillingYear': nextYear,
      'startMeterConfigured': true,
      'electricityStartConfigured': true,
      'waterStartConfigured': true,
    };

    // ---------- preview ----------
    stdout.writeln('--- Preview บิลรายเดือน (${bills.length} เดือน) ---');
    for (final b in bills) {
      final label =
          '${b['year']}-${(b['month'] as int).toString().padLeft(2, '0')}';
      stdout.writeln('  $label  '
          'ไฟ ${(b['electricityCost'] as double).toStringAsFixed(0)} บ. + '
          'น้ำ ${(b['waterCost'] as double).toStringAsFixed(0)} บ. '
          '= ${(b['totalCost'] as double).toStringAsFixed(0)} บ.');
    }
    stdout.writeln('\n--- อุปกรณ์ (${applianceDocs.length} ชิ้น) ---');
    for (final a in applianceDocs) {
      stdout.writeln('  ${a['name']}  ${a['watt']}W');
    }
    stdout.writeln(
        '\nประวัติกรอกมิเตอร์: ${electricityLogs.length} ครั้ง (elec) / '
        '${waterLogs.length} ครั้ง (water) ตลอด ${months.length} เดือน');
    stdout.writeln(
        'ตั้ง billingDay=${options.billingDay}, meterType=${options.isTou ? "tou" : "normal"}, '
        'area=${options.area}, ต้นรอบถัดไป=$nextYear-${nextMonth.toString().padLeft(2, '0')}\n');

    if (!options.apply) {
      stdout.writeln(
          '(นี่คือ dry-run เฉยๆ ยังไม่มีการเขียนข้อมูลใดๆ — รันซ้ำพร้อม --apply เมื่อพร้อม)');
      return;
    }

    if (!options.skipConfirm) {
      stdout.write(
          'กำลังจะเขียน ${bills.length} บิล + ${electricityLogs.length} log ไฟ + '
          '${waterLogs.length} log น้ำ + ${applianceDocs.length} อุปกรณ์ ลง '
          'users/$targetUid — พิมพ์ "yes" เพื่อยืนยัน: ');
      final answer = stdin.readLineSync()?.trim().toLowerCase();
      if (answer != 'yes') {
        stdout.writeln('ยกเลิก ไม่มีการเขียนข้อมูลใดๆ');
        return;
      }
    }

    stdout.writeln('\nกำลัง apply ...');
    var success = 0, failed = 0;

    Future<void> write(String path, Map<String, dynamic> fields) async {
      final id = fields['id'] as String;
      final clean = Map<String, dynamic>.from(fields)
        ..remove('id')
        ..removeWhere((_, v) => v == null);
      try {
        await firestore.patchDocumentFields('$path/$id', clean);
        success++;
      } catch (e) {
        failed++;
        stderr.writeln('  ❌ $path/$id ล้มเหลว: $e');
      }
    }

    for (final b in bills) {
      await write('users/$targetUid/bills', b);
    }
    for (final log in electricityLogs) {
      await write('users/$targetUid/electricity_logs', log);
    }
    for (final log in waterLogs) {
      await write('users/$targetUid/water_logs', log);
    }
    for (final rec in startMeterRecords) {
      await write('users/$targetUid/start_meter_history', rec);
    }
    for (final a in applianceDocs) {
      await write('users/$targetUid/appliances', a);
    }
    try {
      await firestore.patchDocumentFields('users/$targetUid', userUpdate);
      success++;
      stdout.writeln('  ✅ users/$targetUid อัปเดตข้อมูลบัญชีแล้ว');
    } catch (e) {
      failed++;
      stderr.writeln('  ❌ users/$targetUid อัปเดตล้มเหลว: $e');
    }

    stdout.writeln('\nเสร็จสิ้น: สำเร็จ $success รายการ, ล้มเหลว $failed รายการ');
  } finally {
    client.close(force: true);
  }
}

String _hoursToTimeString(double hours) {
  final clamped = hours.clamp(0, 24).toDouble();
  final h = clamped.floor();
  final min = ((clamped - h) * 60).round();
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

// ==================== โมเดลอุปกรณ์ ====================

class _ScheduleBlock {
  final List<int> days; // 0=จันทร์ ... 6=อาทิตย์
  final double hoursPerDay;
  _ScheduleBlock(this.days, this.hoursPerDay);
}

class _ApplianceDef {
  final String name;
  final double watt;
  final List<_ScheduleBlock> scheduleBlocks;
  final bool isAC;
  final double dutyFactor; // เฉพาะแอร์ กันประเมินสูงเกินจริงจาก thermostat cycling
  final double peakFraction; // สัดส่วนชั่วโมงใช้งานที่ตกช่วง On-Peak (จ-ศ 09-22)

  _ApplianceDef({
    required this.name,
    required this.watt,
    required this.scheduleBlocks,
    required this.isAC,
    this.dutyFactor = 1.0,
    required this.peakFraction,
  });

  double get weeklyHours =>
      scheduleBlocks.fold(0.0, (sum, b) => sum + b.hoursPerDay * b.days.length);
}

const _weekdays = [0, 1, 2, 3, 4];
const _weekend = [5, 6];
const _allDays = [0, 1, 2, 3, 4, 5, 6];

List<_ApplianceDef> _buildAppliances(bool isUpcountry) {
  if (!isUpcountry) {
    return [
      _ApplianceDef(
        name: 'ตู้เย็น',
        watt: 100,
        scheduleBlocks: [_ScheduleBlock(_allDays, 24)],
        isAC: false,
        peakFraction: 0.387,
      ),
      _ApplianceDef(
        name: 'แอร์ห้องนอนใหญ่ (Inverter)',
        watt: 900,
        scheduleBlocks: [_ScheduleBlock(_allDays, 8)],
        isAC: true,
        dutyFactor: 0.35,
        peakFraction: 0.0,
      ),
      _ApplianceDef(
        name: 'แอร์ห้องลูก (Inverter)',
        watt: 750,
        scheduleBlocks: [_ScheduleBlock(_allDays, 5)],
        isAC: true,
        dutyFactor: 0.30,
        peakFraction: 0.0,
      ),
      _ApplianceDef(
        name: 'แอร์ห้องนั่งเล่น (Fixed Speed)',
        watt: 1200,
        scheduleBlocks: [
          _ScheduleBlock(_weekdays, 4),
          _ScheduleBlock(_weekend, 5),
        ],
        isAC: true,
        dutyFactor: 0.35,
        peakFraction: 0.667,
      ),
      _ApplianceDef(
        name: 'เครื่องทำน้ำอุ่นไฟฟ้า',
        watt: 4500,
        scheduleBlocks: [
          _ScheduleBlock(_weekdays, 1.4),
          _ScheduleBlock(_weekend, 1.4),
        ],
        isAC: false,
        peakFraction: 0.357,
      ),
      _ApplianceDef(
        name: 'หม้อหุงข้าวไฟฟ้า',
        watt: 600,
        scheduleBlocks: [
          _ScheduleBlock(_weekdays, 1),
          _ScheduleBlock(_weekend, 1),
        ],
        isAC: false,
        peakFraction: 0.714,
      ),
      _ApplianceDef(
        name: 'เตาไมโครเวฟ',
        watt: 1200,
        scheduleBlocks: [
          _ScheduleBlock(_weekdays, 0.25),
          _ScheduleBlock(_weekend, 0.25),
        ],
        isAC: false,
        peakFraction: 0.714,
      ),
      _ApplianceDef(
        name: 'พัดลมไฟฟ้า',
        watt: 50,
        scheduleBlocks: [
          _ScheduleBlock(_weekdays, 4),
          _ScheduleBlock(_weekend, 5),
        ],
        isAC: false,
        peakFraction: 0.667,
      ),
      _ApplianceDef(
        name: 'เครื่องซักผ้า',
        watt: 500,
        scheduleBlocks: [_ScheduleBlock(_weekend, 1)],
        isAC: false,
        peakFraction: 0.0,
      ),
      _ApplianceDef(
        name: 'เตารีดไฟฟ้า',
        watt: 1200,
        scheduleBlocks: [
          _ScheduleBlock([2], 1)
        ],
        isAC: false,
        peakFraction: 0.5,
      ),
      _ApplianceDef(
        name: 'ไดร์เป่าผม',
        watt: 1200,
        scheduleBlocks: [_ScheduleBlock(_allDays, 0.1)],
        isAC: false,
        peakFraction: 0.0,
      ),
    ];
  } else {
    return [
      _ApplianceDef(
        name: 'ตู้เย็น',
        watt: 100,
        scheduleBlocks: [_ScheduleBlock(_allDays, 24)],
        isAC: false,
        peakFraction: 0.387,
      ),
      _ApplianceDef(
        name: 'แอร์ห้องนอนใหญ่ (Inverter)',
        watt: 800,
        scheduleBlocks: [_ScheduleBlock(_allDays, 6)],
        isAC: true,
        dutyFactor: 0.30,
        peakFraction: 0.0,
      ),
      _ApplianceDef(
        name: 'แอร์ห้องนั่งเล่น (Fixed Speed)',
        watt: 1000,
        scheduleBlocks: [
          _ScheduleBlock(_weekdays, 3),
          _ScheduleBlock(_weekend, 4),
        ],
        isAC: true,
        dutyFactor: 0.30,
        peakFraction: 0.652,
      ),
      _ApplianceDef(
        name: 'เครื่องทำน้ำอุ่นไฟฟ้า',
        watt: 4000,
        scheduleBlocks: [
          _ScheduleBlock(_weekdays, 1.2),
          _ScheduleBlock(_weekend, 1.2),
        ],
        isAC: false,
        peakFraction: 0.357,
      ),
      _ApplianceDef(
        name: 'หม้อหุงข้าวไฟฟ้า',
        watt: 600,
        scheduleBlocks: [
          _ScheduleBlock(_weekdays, 1),
          _ScheduleBlock(_weekend, 1),
        ],
        isAC: false,
        peakFraction: 0.714,
      ),
      _ApplianceDef(
        name: 'พัดลมไฟฟ้า',
        watt: 50,
        scheduleBlocks: [
          _ScheduleBlock(_weekdays, 5),
          _ScheduleBlock(_weekend, 6),
        ],
        isAC: false,
        peakFraction: 0.676,
      ),
      _ApplianceDef(
        name: 'เครื่องซักผ้า',
        watt: 500,
        scheduleBlocks: [_ScheduleBlock(_weekend, 1)],
        isAC: false,
        peakFraction: 0.0,
      ),
      _ApplianceDef(
        name: 'เตารีดไฟฟ้า',
        watt: 1200,
        scheduleBlocks: [
          _ScheduleBlock([2], 1)
        ],
        isAC: false,
        peakFraction: 0.5,
      ),
      _ApplianceDef(
        name: 'ไดร์เป่าผม',
        watt: 1200,
        scheduleBlocks: [_ScheduleBlock(_allDays, 0.1)],
        isAC: false,
        peakFraction: 0.0,
      ),
    ];
  }
}

// ==================== คำนวณการใช้ไฟ/น้ำรายเดือนจากอุปกรณ์ + ฤดูกาล ====================

class _MonthPlan {
  final int year;
  final int month;
  final double totalKwh; // ใช้เมื่อ meterType ปกติ
  final double peakKwh; // ใช้เมื่อ TOU
  final double offPeakKwh;
  final double waterUnits;

  _MonthPlan({
    required this.year,
    required this.month,
    required this.totalKwh,
    required this.peakKwh,
    required this.offPeakKwh,
    required this.waterUnits,
  });
}

double _acSeasonMultiplier(int month, bool isUpcountry) {
  final hot = isUpcountry ? 1.35 : 1.45;
  if (month == 3 || month == 4 || month == 5) return hot; // ร้อน
  if (month >= 6 && month <= 10) return 1.0; // ฝน
  return 0.55; // หนาว (พ.ย.-ก.พ.)
}

double _waterSeasonMultiplier(int month) {
  if (month == 3 || month == 4 || month == 5) return 1.15; // ร้อน อาบน้ำบ่อยขึ้น
  if (month >= 6 && month <= 10) return 1.0; // ฝน
  return 0.90; // หนาว
}

const double _weeksPerMonth = 4.348;

_MonthPlan _computeMonth(int year, int month, int monthIndex,
    List<_ApplianceDef> appliances, bool isTou, bool isUpcountry) {
  double totalKwh = 0, peakKwh = 0, offPeakKwh = 0;
  for (final a in appliances) {
    var monthly = a.watt / 1000 * a.weeklyHours * _weeksPerMonth;
    if (a.isAC) {
      monthly *= a.dutyFactor * _acSeasonMultiplier(month, isUpcountry);
    }
    totalKwh += monthly;
    peakKwh += monthly * a.peakFraction;
    offPeakKwh += monthly * (1 - a.peakFraction);
  }

  // trend เติบโตเบาๆ 3%/ปี + noise สุ่มรายเดือน ±15% (seed ตายตัว รันซ้ำได้ผลเดิม)
  final trend = pow(1.03, monthIndex / 12).toDouble();
  final elecRng = Random(year * 100 + month + 1);
  final elecNoise = 1 + (elecRng.nextDouble() * 0.30 - 0.15);
  final elecFactor = trend * elecNoise;
  totalKwh *= elecFactor;
  peakKwh *= elecFactor;
  offPeakKwh *= elecFactor;

  final waterBase = isUpcountry ? 14.0 : 17.0;
  final waterRng = Random(year * 100 + month + 2);
  final waterNoise = 1 + (waterRng.nextDouble() * 0.20 - 0.10);
  final waterUnits = waterBase *
      _waterSeasonMultiplier(month) *
      trend *
      waterNoise;

  return _MonthPlan(
    year: year,
    month: month,
    totalKwh: double.parse(totalKwh.toStringAsFixed(1)),
    peakKwh: double.parse(peakKwh.toStringAsFixed(1)),
    offPeakKwh: double.parse(offPeakKwh.toStringAsFixed(1)),
    waterUnits: double.parse(waterUnits.toStringAsFixed(1)),
  );
}

// ==================== แบ่งวันที่/สัดส่วนสะสมสำหรับ log หลายครั้ง/เดือน ====================
// (เหมือนกับใน import_case_logs.dart เป๊ะ)

List<DateTime> _splitDatesAscending(
    DateTime start, DateTime end, int n, Random rng) {
  if (n <= 1) return [end];
  final totalDays = end.difference(start).inDays;
  final safeTotalDays = totalDays < (n - 1) ? (n - 1) : totalDays;
  final result = <DateTime>[];
  for (var i = 0; i < n - 1; i++) {
    final base = (safeTotalDays * (i + 1) / n).floor();
    final jitter = safeTotalDays > n
        ? rng.nextInt((safeTotalDays / n).ceil()) -
            (safeTotalDays / n / 2).floor()
        : 0;
    var offset = base + jitter;
    if (offset < i) offset = i;
    if (offset >= safeTotalDays) offset = safeTotalDays - 1;
    result.add(start.add(Duration(days: offset)));
  }
  for (var i = 1; i < result.length; i++) {
    if (!result[i].isAfter(result[i - 1])) {
      result[i] = result[i - 1].add(const Duration(days: 1));
    }
  }
  if (result.isNotEmpty && !end.isAfter(result.last)) {
    result[result.length - 1] = end.subtract(const Duration(days: 1));
  }
  result.add(end);
  return result;
}

List<double> _splitIncreasingFractions(int n, Random rng) {
  if (n <= 1) return [1.0];
  final weights = List.generate(n, (_) => 0.3 + rng.nextDouble());
  final total = weights.reduce((a, b) => a + b);
  var cumulative = 0.0;
  final fractions = <double>[];
  for (final w in weights) {
    cumulative += w;
    fractions.add(cumulative / total);
  }
  return fractions;
}

DateTime _safeBillingDate(int year, int month, int billingDay) {
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final safeDay = billingDay > lastDayOfMonth ? lastDayOfMonth : billingDay;
  return DateTime(year, month, safeDay);
}

// ==================== พอร์ตจาก lib/utils/calculator.dart (ต้องตรงกันเป๊ะ) ====================

const double _vatRate = 1.07;
const double _electricityTier1Rate = 3.2484;
const double _electricityTier2Rate = 4.2218;
const double _electricityTier3Rate = 4.4217;
const double _electricityServiceFee = 24.62;
const double _touPeakRate = 5.7982;
const double _touOffPeakRate = 2.6369;

double _calculateEnergyRateOver150(double units) {
  double cost = 0;
  if (units <= 150) {
    cost = units * _electricityTier1Rate;
  } else if (units <= 400) {
    cost = 150 * _electricityTier1Rate;
    cost += (units - 150) * _electricityTier2Rate;
  } else {
    cost = 150 * _electricityTier1Rate;
    cost += 250 * _electricityTier2Rate;
    cost += (units - 400) * _electricityTier3Rate;
  }
  return cost;
}

double _calculateElectricity(double units, String area, double ftRate) {
  if (units <= 0) return 0;
  double energyCost = _calculateEnergyRateOver150(units);
  double ftCost = units * ftRate;
  double total = (energyCost + _electricityServiceFee + ftCost) * _vatRate;
  return double.parse(total.toStringAsFixed(2));
}

double _calculateElectricityTOU({
  required double peakUnits,
  required double offPeakUnits,
  required double ftRate,
}) {
  if (peakUnits <= 0 && offPeakUnits <= 0) return 0;
  double totalUnits = peakUnits + offPeakUnits;
  double energyCost =
      (peakUnits * _touPeakRate) + (offPeakUnits * _touOffPeakRate);
  double ftCost = totalUnits * ftRate;
  double total = (energyCost + _electricityServiceFee + ftCost) * _vatRate;
  return double.parse(total.toStringAsFixed(2));
}

const double _waterMwaTier1 = 8.50;
const double _waterMwaTier2 = 10.03;
const double _waterMwaTier3 = 10.35;
const double _waterMwaTier4 = 10.68;
const double _waterMwaTier5 = 11.00;
const double _waterMwaTier6 = 11.33;
const double _waterMwaTier7 = 12.50;
const double _waterMwaTier8 = 12.82;
const double _waterMwaTier9 = 13.15;
const double _waterMwaTier10 = 13.47;
const double _waterMwaTier11 = 13.80;
const double _waterMwaTier12 = 14.45;
const double _waterMwaServiceFee = 25.00;
const double _waterMwaRawWaterFee = 0.15;
const double _waterMwaMinimum = 45.00;

double _calculateWaterMWA(double units) {
  if (units <= 0) return 0;
  double cost = 0;
  if (units <= 30) {
    cost = units * _waterMwaTier1;
  } else if (units <= 40) {
    cost = 30 * _waterMwaTier1 + (units - 30) * _waterMwaTier2;
  } else if (units <= 50) {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        (units - 40) * _waterMwaTier3;
  } else if (units <= 60) {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        10 * _waterMwaTier3 +
        (units - 50) * _waterMwaTier4;
  } else if (units <= 70) {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        10 * _waterMwaTier3 +
        10 * _waterMwaTier4 +
        (units - 60) * _waterMwaTier5;
  } else if (units <= 80) {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        10 * _waterMwaTier3 +
        10 * _waterMwaTier4 +
        10 * _waterMwaTier5 +
        (units - 70) * _waterMwaTier6;
  } else if (units <= 90) {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        10 * _waterMwaTier3 +
        10 * _waterMwaTier4 +
        10 * _waterMwaTier5 +
        10 * _waterMwaTier6 +
        (units - 80) * _waterMwaTier7;
  } else if (units <= 100) {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        10 * _waterMwaTier3 +
        10 * _waterMwaTier4 +
        10 * _waterMwaTier5 +
        10 * _waterMwaTier6 +
        10 * _waterMwaTier7 +
        (units - 90) * _waterMwaTier8;
  } else if (units <= 120) {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        10 * _waterMwaTier3 +
        10 * _waterMwaTier4 +
        10 * _waterMwaTier5 +
        10 * _waterMwaTier6 +
        10 * _waterMwaTier7 +
        10 * _waterMwaTier8 +
        (units - 100) * _waterMwaTier9;
  } else if (units <= 160) {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        10 * _waterMwaTier3 +
        10 * _waterMwaTier4 +
        10 * _waterMwaTier5 +
        10 * _waterMwaTier6 +
        10 * _waterMwaTier7 +
        10 * _waterMwaTier8 +
        20 * _waterMwaTier9 +
        (units - 120) * _waterMwaTier10;
  } else if (units <= 200) {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        10 * _waterMwaTier3 +
        10 * _waterMwaTier4 +
        10 * _waterMwaTier5 +
        10 * _waterMwaTier6 +
        10 * _waterMwaTier7 +
        10 * _waterMwaTier8 +
        20 * _waterMwaTier9 +
        40 * _waterMwaTier10 +
        (units - 160) * _waterMwaTier11;
  } else {
    cost = 30 * _waterMwaTier1 +
        10 * _waterMwaTier2 +
        10 * _waterMwaTier3 +
        10 * _waterMwaTier4 +
        10 * _waterMwaTier5 +
        10 * _waterMwaTier6 +
        10 * _waterMwaTier7 +
        10 * _waterMwaTier8 +
        20 * _waterMwaTier9 +
        40 * _waterMwaTier10 +
        40 * _waterMwaTier11 +
        (units - 200) * _waterMwaTier12;
  }
  double subtotal = cost + _waterMwaServiceFee + units * _waterMwaRawWaterFee;
  if (subtotal < _waterMwaMinimum) subtotal = _waterMwaMinimum;
  double total = subtotal * _vatRate;
  return double.parse(total.toStringAsFixed(2));
}

const double _waterPwaTier1 = 10.20;
const double _waterPwaTier2 = 16.00;
const double _waterPwaTier3 = 19.00;
const double _waterPwaTier4 = 21.20;
const double _waterPwaTier5 = 21.60;
const double _waterPwaTier6 = 21.65;
const double _waterPwaTier7 = 21.70;
const double _waterPwaTier8 = 21.75;
const double _waterPwaTier9 = 21.80;
const double _waterPwaTier10 = 21.85;
const double _waterPwaTier11 = 21.90;
const double _waterPwaServiceFee = 30.00;
const double _waterPwaMinimum = 50.00;

double _calculateWaterPWA(double units) {
  if (units <= 0) return 0;
  double cost = 0;
  if (units <= 10) {
    cost = units * _waterPwaTier1;
  } else if (units <= 20) {
    cost = 10 * _waterPwaTier1 + (units - 10) * _waterPwaTier2;
  } else if (units <= 30) {
    cost = 10 * _waterPwaTier1 +
        10 * _waterPwaTier2 +
        (units - 20) * _waterPwaTier3;
  } else if (units <= 50) {
    cost = 10 * _waterPwaTier1 +
        10 * _waterPwaTier2 +
        10 * _waterPwaTier3 +
        (units - 30) * _waterPwaTier4;
  } else {
    cost = 10 * _waterPwaTier1 +
        10 * _waterPwaTier2 +
        10 * _waterPwaTier3 +
        20 * _waterPwaTier4;
    if (units <= 80) {
      cost += (units - 50) * _waterPwaTier5;
    } else if (units <= 100) {
      cost += 30 * _waterPwaTier5 + (units - 80) * _waterPwaTier6;
    } else if (units <= 300) {
      cost += 30 * _waterPwaTier5 +
          20 * _waterPwaTier6 +
          (units - 100) * _waterPwaTier7;
    } else if (units <= 1000) {
      cost += 30 * _waterPwaTier5 +
          20 * _waterPwaTier6 +
          200 * _waterPwaTier7 +
          (units - 300) * _waterPwaTier8;
    } else if (units <= 2000) {
      cost += 30 * _waterPwaTier5 +
          20 * _waterPwaTier6 +
          200 * _waterPwaTier7 +
          700 * _waterPwaTier8 +
          (units - 1000) * _waterPwaTier9;
    } else if (units <= 3000) {
      cost += 30 * _waterPwaTier5 +
          20 * _waterPwaTier6 +
          200 * _waterPwaTier7 +
          700 * _waterPwaTier8 +
          1000 * _waterPwaTier9 +
          (units - 2000) * _waterPwaTier10;
    } else {
      cost += 30 * _waterPwaTier5 +
          20 * _waterPwaTier6 +
          200 * _waterPwaTier7 +
          700 * _waterPwaTier8 +
          1000 * _waterPwaTier9 +
          1000 * _waterPwaTier10 +
          (units - 3000) * _waterPwaTier11;
    }
  }
  double subtotal = cost + _waterPwaServiceFee;
  if (subtotal < _waterPwaMinimum) subtotal = _waterPwaMinimum;
  double total = subtotal * _vatRate;
  return double.parse(total.toStringAsFixed(2));
}

Future<double> _getFtRate(_FirestoreRestClient firestore) async {
  try {
    final doc = await firestore.getDocument('app_config/electricity_rates');
    if (doc == null) return 0.1623;
    final fields = _decodeFields(doc['fields'] as Map<String, dynamic>);
    return (fields['ft_rate'] as num?)?.toDouble() ?? 0.1623;
  } catch (_) {
    return 0.1623;
  }
}

// ==================== Firebase Auth (Identity Toolkit) REST ====================

Future<Map<String, dynamic>> _signIn({
  required HttpClient client,
  required String apiKey,
  required String email,
  required String password,
}) async {
  final uri = Uri.parse('$_identityToolkitUrl?key=$apiKey');
  final request = await client.postUrl(uri);
  request.headers.set('Content-Type', 'application/json');
  request.add(utf8.encode(jsonEncode({
    'email': email,
    'password': password,
    'returnSecureToken': true,
  })));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw Exception('sign-in ล้มเหลว (${response.statusCode}): $body');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

// ==================== Firestore REST client ====================

class _FirestoreRestClient {
  _FirestoreRestClient({
    required this.client,
    required this.projectId,
    required this.idToken,
  });

  final HttpClient client;
  final String projectId;
  final String idToken;

  String get _baseUrl =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  Future<Map<String, dynamic>?> getDocument(String relativePath) async {
    final uri = Uri.parse('$_baseUrl/$relativePath');
    final request = await client.getUrl(uri);
    request.headers.set('Authorization', 'Bearer $idToken');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('อ่าน $relativePath ล้มเหลว (${response.statusCode}): $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<void> patchDocumentFields(
      String relativePath, Map<String, dynamic> fieldsToUpdate) async {
    final maskParams =
        fieldsToUpdate.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
    final uri = Uri.parse('$_baseUrl/$relativePath?$maskParams');
    final request = await client.patchUrl(uri);
    request.headers.set('Authorization', 'Bearer $idToken');
    request.headers.set('Content-Type', 'application/json');
    request.add(utf8.encode(jsonEncode({'fields': _encodeFields(fieldsToUpdate)})));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception('เขียน $relativePath ล้มเหลว (${response.statusCode}): $body');
    }
  }
}

Map<String, dynamic> _encodeFields(Map<String, dynamic> data) {
  final result = <String, dynamic>{};
  for (final entry in data.entries) {
    result[entry.key] = _encodeValue(entry.value);
  }
  return result;
}

Map<String, dynamic> _encodeValue(dynamic value) {
  if (value == null) return {'nullValue': null};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': value.toString()};
  if (value is double) return {'doubleValue': value};
  if (value is String) return {'stringValue': value};
  if (value is List) {
    return {
      'arrayValue': {
        'values': value.map((v) => _encodeValue(v)).toList(),
      }
    };
  }
  if (value is Map) {
    return {
      'mapValue': {
        'fields': value
            .map((k, v) => MapEntry(k.toString(), _encodeValue(v))),
      }
    };
  }
  throw Exception('ไม่รู้จักชนิดข้อมูล: ${value.runtimeType}');
}

Map<String, dynamic> _decodeFields(Map<String, dynamic> fields) {
  final result = <String, dynamic>{};
  for (final entry in fields.entries) {
    result[entry.key] = _decodeValue(entry.value as Map<String, dynamic>);
  }
  return result;
}

dynamic _decodeValue(Map<String, dynamic> value) {
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('integerValue')) {
    return int.parse(value['integerValue'] as String);
  }
  if (value.containsKey('doubleValue')) {
    final v = value['doubleValue'];
    return v is int ? v.toDouble() : v as double;
  }
  if (value.containsKey('booleanValue')) return value['booleanValue'];
  if (value.containsKey('nullValue')) return null;
  throw Exception('ไม่รู้จักชนิดฟิลด์ Firestore: ${value.keys}');
}

// ==================== CLI args ====================

class _Options {
  final String caseName;
  final bool isUpcountry;
  final bool isTou;
  final String area;
  final String projectId;
  final String apiKey;
  final String email;
  final String password;
  final String? uid;
  final int billingDay;
  final double skipRate;
  final int months;
  final int readingsMin;
  final int readingsMax;
  final double elecStart;
  final double waterStart;
  final bool apply;
  final bool skipConfirm;

  _Options({
    required this.caseName,
    required this.isUpcountry,
    required this.isTou,
    required this.area,
    required this.projectId,
    required this.apiKey,
    required this.email,
    required this.password,
    required this.uid,
    required this.billingDay,
    required this.skipRate,
    required this.months,
    required this.readingsMin,
    required this.readingsMax,
    required this.elecStart,
    required this.waterStart,
    required this.apply,
    required this.skipConfirm,
  });
}

_Options? _parseArgs(List<String> args) {
  String? caseName, projectId, apiKey, email, password, uid;
  int billingDay = 30;
  double skipRate = 0.0;
  int months = 36;
  int readingsMin = 4, readingsMax = 5;
  double elecStart = 0, waterStart = 0;
  bool apply = false, skipConfirm = false;

  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      _printHelp();
      return null;
    } else if (arg == '--apply') {
      apply = true;
    } else if (arg == '--yes') {
      skipConfirm = true;
    } else if (arg.startsWith('--case=')) {
      caseName = arg.substring('--case='.length);
    } else if (arg.startsWith('--project-id=')) {
      projectId = arg.substring('--project-id='.length);
    } else if (arg.startsWith('--api-key=')) {
      apiKey = arg.substring('--api-key='.length);
    } else if (arg.startsWith('--email=')) {
      email = arg.substring('--email='.length);
    } else if (arg.startsWith('--password=')) {
      password = arg.substring('--password='.length);
    } else if (arg.startsWith('--uid=')) {
      uid = arg.substring('--uid='.length);
    } else if (arg.startsWith('--billing-day=')) {
      billingDay = int.parse(arg.substring('--billing-day='.length));
    } else if (arg.startsWith('--skip-rate=')) {
      skipRate = double.parse(arg.substring('--skip-rate='.length));
    } else if (arg.startsWith('--months=')) {
      months = int.parse(arg.substring('--months='.length));
    } else if (arg.startsWith('--readings-min=')) {
      readingsMin = int.parse(arg.substring('--readings-min='.length));
    } else if (arg.startsWith('--readings-max=')) {
      readingsMax = int.parse(arg.substring('--readings-max='.length));
    } else if (arg.startsWith('--elec-start=')) {
      elecStart = double.parse(arg.substring('--elec-start='.length));
    } else if (arg.startsWith('--water-start=')) {
      waterStart = double.parse(arg.substring('--water-start='.length));
    } else {
      stderr.writeln('ไม่รู้จัก argument: $arg');
      _printHelp();
      exitCode = 1;
      return null;
    }
  }

  const validCases = [
    'bangkok_normal',
    'bangkok_tou',
    'upcountry_normal',
    'upcountry_tou',
  ];
  if (caseName == null || !validCases.contains(caseName)) {
    stderr.writeln(
        '--case ต้องเป็นหนึ่งใน: ${validCases.join(', ')}\n');
    _printHelp();
    exitCode = 1;
    return null;
  }
  if (projectId == null || apiKey == null || email == null) {
    stderr.writeln(
        'ขาด argument ที่จำเป็น (--project-id, --api-key, --email)\n');
    _printHelp();
    exitCode = 1;
    return null;
  }
  if (readingsMin < 1 || readingsMax < readingsMin) {
    stderr.writeln(
        '--readings-min ต้อง >= 1 และ --readings-max ต้อง >= --readings-min');
    exitCode = 1;
    return null;
  }
  if (skipRate < 0 || skipRate > 1) {
    stderr.writeln('--skip-rate ต้องอยู่ระหว่าง 0.0-1.0');
    exitCode = 1;
    return null;
  }

  final isUpcountry = caseName.startsWith('upcountry');
  final isTou = caseName.endsWith('_tou');
  final area = isUpcountry ? 'province' : 'bangkok';

  if (password == null) {
    stdout.write('Password สำหรับ $email: ');
    var hideInput = false;
    try {
      stdin.echoMode = false;
      hideInput = true;
    } catch (_) {}
    password = stdin.readLineSync() ?? '';
    if (hideInput) stdin.echoMode = true;
    stdout.writeln();
  }

  return _Options(
    caseName: caseName,
    isUpcountry: isUpcountry,
    isTou: isTou,
    area: area,
    projectId: projectId,
    apiKey: apiKey,
    email: email,
    password: password,
    uid: uid,
    billingDay: billingDay,
    skipRate: skipRate,
    months: months,
    readingsMin: readingsMin,
    readingsMax: readingsMax,
    elecStart: elecStart,
    waterStart: waterStart,
    apply: apply,
    skipConfirm: skipConfirm,
  );
}

void _printHelp() {
  stdout.writeln('''
วิธีใช้:
  dart run tool/forecast_synth/generate_household.dart \\
    --case=bangkok_normal|bangkok_tou|upcountry_normal|upcountry_tou \\
    --project-id=ID --api-key=KEY --email=EMAIL [options]

Required:
  --case=...             ประเภทบ้าน (กำหนด area + meterType อัตโนมัติ)
  --project-id=ID        Firebase project ID
  --api-key=KEY          Firebase Web API Key
  --email=EMAIL          อีเมลของบัญชีที่จะเพิ่มข้อมูลให้

Optional:
  --password=PASSWORD    ถ้าไม่ใส่จะถามแบบซ่อนตัวอักษรตอนรัน
  --uid=UID               เขียนให้ uid อื่นที่ไม่ใช่บัญชีที่ sign-in
  --billing-day=DAY      วันตัดรอบบิล 1-31 (default: 30)
  --skip-rate=0.0-1.0    สัดส่วนเดือนที่ "ลืมออกบิล" สุ่มข้าม (default: 0 = ครบทุกเดือน)
  --months=N             จำนวนเดือนย้อนหลังถึงปัจจุบัน (default: 36 = 3 ปี)
  --readings-min=N       จำนวนครั้งกรอกมิเตอร์ต่อเดือน ขั้นต่ำ (default: 4)
  --readings-max=N       จำนวนครั้งกรอกมิเตอร์ต่อเดือน สูงสุด (default: 5)
  --elec-start=NUMBER    เลขมิเตอร์ไฟสะสมตั้งต้นก่อนเดือนแรก (default: 0)
  --water-start=NUMBER   เลขมิเตอร์น้ำสะสมตั้งต้นก่อนเดือนแรก (default: 0)
  --apply                เขียนข้อมูลจริง (ไม่ใส่ = dry-run แสดง preview เฉยๆ)
  --yes                  ข้ามการถามยืนยันตอน apply
  --help                 แสดงข้อความนี้
''');
}