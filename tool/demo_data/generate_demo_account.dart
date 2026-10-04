// ignore_for_file: avoid_print
//
// tool/demo_data/generate_demo_account.dart
//
// สร้างข้อมูลเดโมให้บัญชีที่สมัครไว้แล้ว 1 บัญชี ตาม 4 เคสหลักของแอป:
//   bangkok_normal / bangkok_tou / upcountry_normal / upcountry_tou
//
// สิ่งที่เขียนลง Firestore (users/{uid}):
//   - บิลย้อนหลังที่ระบบปิดรอบให้แล้ว (source 'compiled', id เดียวกับที่
//     FirestoreService.compileBill ใช้) ตามจำนวนเดือนที่กำหนด
//   - เลขมิเตอร์ต้นรอบของทุกรอบ (start_meter_history) รวมรอบปัจจุบัน
//   - ประวัติบันทึกมิเตอร์รายวัน 4-5 ครั้งต่อรอบ และรอบปัจจุบันถึงเมื่อวาน
//   - รายการอุปกรณ์ในบ้าน ที่สอดคล้องกับปริมาณการใช้ไฟ
//   - ข้อมูลบัญชี: พื้นที่, ประเภทมิเตอร์, วันตัดรอบ, เลขต้นรอบรอบปัจจุบัน
//
// กติกาเดียวกับแอป (สำคัญ — ถ้าไม่ตรง หน้าวิเคราะห์/แดชบอร์ดจะเพี้ยน):
//   - ขอบเขตรอบบิลใช้ EnergyForecaster ของแอปตรงๆ (วันตัดรอบเป็นวันแรกของ
//     รอบใหม่) บันทึกมิเตอร์ทุกครั้งอยู่ภายในรอบ ไม่ตกวันตัดรอบ
//   - บิลตั้งชื่อด้วยเดือนที่ปิดรอบ ส่วนเลขต้นรอบตั้งชื่อด้วยเดือนที่รอบเริ่ม
//   - การใช้ไฟ/น้ำรายเดือน = ค่าเฉลี่ยจากอุปกรณ์ x ตัวคูณฤดูกาลจริงของแอป
//     (lib/utils/seasonal_curves.dart) x แนวโน้มเล็กน้อย x ความผันผวนสุ่ม
//     (seed ตายตัว รันซ้ำได้ผลเดิม)
//   - ค่าไฟ/ค่าน้ำคำนวณด้วยสูตรที่คัดลอกจาก lib/utils/calculator.dart
//     (ไฟล์นั้น import cloud_firestore จึงเรียกจาก `dart run` ตรงๆ ไม่ได้)
//     ถ้าแก้อัตราในแอป ต้องแก้ที่นี่ด้วย
//
// ต้องมีบัญชีก่อน: สคริปต์ sign-in ด้วยอีเมล/รหัสผ่าน (สร้างบัญชีใหม่ให้ไม่ได้)
// ให้สมัครบัญชีในแอปและทำขั้นตอนตั้งค่าเริ่มต้นให้เสร็จก่อน
//
// วิธีใช้ (dry-run ก่อนเสมอ แล้วค่อย --apply):
//   dart run tool/demo_data/generate_demo_account.dart \
//     --case=bangkok_normal \
//     --project-id=YOUR_PROJECT_ID \
//     --api-key=YOUR_FIREBASE_WEB_API_KEY \
//     --email=demo1@example.com
//
//   รันซ้ำบัญชีเดิมพร้อม --reset เพื่อล้างข้อมูลเดิมทั้งหมด (บิล, บันทึก
//   มิเตอร์, เลขต้นรอบ, อุปกรณ์, รายจ่ายประจำ) ก่อนเขียนชุดใหม่
//   ดูตัวเลือกทั้งหมดด้วย --help

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:energy_home/utils/forecaster.dart';
import 'package:energy_home/utils/seasonal_curves.dart';

const _identityToolkitUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';

// subcollection ที่ --reset จะล้างก่อนเขียนข้อมูลใหม่
const _resetCollections = [
  'bills',
  'electricity_logs',
  'water_logs',
  'start_meter_history',
  'appliances',
  'fixed_costs',
];

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) return;

  final now = DateTime.now();
  final plan = _buildPlan(options, now);
  _printPreview(options, plan);

  // สร้างเอกสารชุดตัวอย่าง (ยังไม่ต้อง sign-in) เพื่อตรวจกติกาก่อนเขียนจริง
  final preview = _buildDocuments(plan, options, 'preview', 0.1623);
  final problems = _validate(preview, plan, now);
  print('\nเอกสารที่จะเขียน: ${preview.entries.map((e) => '${e.key} ${e.value.length}').join(', ')}');
  if (problems.isNotEmpty) {
    stderr.writeln('ตรวจพบปัญหา ${problems.length} จุด — ยกเลิก:');
    for (final p in problems.take(10)) {
      stderr.writeln('  - $p');
    }
    exitCode = 1;
    return;
  }
  print('ตรวจแล้ว: บันทึกมิเตอร์ทุกครั้งอยู่ในรอบของตัวเอง เลขมิเตอร์ไม่ลดลง');

  if (!options.apply) {
    print('\n(dry-run — ยังไม่มีการเขียนข้อมูล รันซ้ำพร้อม --apply เมื่อพร้อม)');
    return;
  }

  final client = HttpClient();
  try {
    print('\nกำลัง sign-in ด้วย ${options.email} ...');
    final auth = await _signIn(client, options.apiKey, options.email, options.password);
    final uid = auth['localId'] as String;
    final firestore = _FirestoreRestClient(client, options.projectId, auth['idToken'] as String);
    print('sign-in สำเร็จ (uid: $uid)');

    final ftRate = await _getFtRate(firestore);
    final docs = _buildDocuments(plan, options, uid, ftRate);

    if (!options.skipConfirm) {
      stdout.write('\nกำลังจะเขียนข้อมูลเดโมลง users/$uid'
          '${options.reset ? ' (ล้างข้อมูลเดิมทั้งหมดก่อน)' : ''} — พิมพ์ "yes" เพื่อยืนยัน: ');
      if (stdin.readLineSync()?.trim().toLowerCase() != 'yes') {
        print('ยกเลิก ไม่มีการเขียนข้อมูลใดๆ');
        return;
      }
    }

    if (options.reset) {
      for (final collection in _resetCollections) {
        final existing = await firestore.listDocuments('users/$uid/$collection');
        for (final doc in existing) {
          await firestore.deleteDocument(doc['name'] as String);
        }
        print('  ล้าง $collection (${existing.length} รายการ)');
      }
    }

    var written = 0;
    for (final entry in docs.entries) {
      for (final doc in entry.value) {
        final fields = Map<String, dynamic>.from(doc)..removeWhere((_, v) => v == null);
        await firestore.patchDocument('users/$uid/${entry.key}/${doc['id']}', fields);
        written++;
      }
      print('  เขียน ${entry.key} ${entry.value.length} รายการ');
    }
    await firestore.patchDocument('users/$uid', _userUpdate(plan, options));
    print('  อัปเดตข้อมูลบัญชีแล้ว');
    print('\nเสร็จสิ้น เขียนทั้งหมด ${written + 1} รายการ');
  } finally {
    client.close(force: true);
  }
}

// ==================== แผนข้อมูลรายรอบบิล ====================

class _Cycle {
  _Cycle(this.start, this.end, this.usage);
  final DateTime start; // วันตัดรอบที่เริ่มรอบนี้ (รวมวันนั้น)
  final DateTime end; // วันตัดรอบถัดไป (ไม่รวม)
  final _Usage usage; // การใช้ทั้งรอบ (รอบปัจจุบัน = คาดการณ์ทั้งรอบ)
}

class _Usage {
  _Usage(this.peakKwh, this.offPeakKwh, this.waterUnits);
  final double peakKwh; // มิเตอร์ปกติ: ใช้ peakKwh เป็นยอดรวมทั้งหมด
  final double offPeakKwh;
  final double waterUnits;
  double get totalKwh => peakKwh + offPeakKwh;
}

class _Plan {
  _Plan(this.closedCycles, this.currentCycle, this.appliances);
  final List<_Cycle> closedCycles; // เก่า -> ใหม่
  final _Cycle currentCycle;
  final List<_Appliance> appliances;
}

_Plan _buildPlan(_Options o, DateTime now) {
  final appliances = _appliancesFor(o.isUpcountry);
  final currentStart = EnergyForecaster.getCycleStart(now, o.billingDay);
  final currentEnd = EnergyForecaster.getCycleEnd(now, o.billingDay);

  final starts = <DateTime>[currentStart];
  for (var i = 0; i < o.months; i++) {
    starts.insert(0, EnergyForecaster.getPreviousCycleStart(starts.first, o.billingDay));
  }
  final closed = <_Cycle>[];
  for (var i = 0; i < o.months; i++) {
    final end = starts[i + 1];
    closed.add(_Cycle(starts[i], end, _usageForBillMonth(o, appliances, end, i)));
  }
  final current = _Cycle(currentStart, currentEnd,
      _usageForBillMonth(o, appliances, currentEnd, o.months));
  return _Plan(closed, current, appliances);
}

// การใช้ของรอบที่ปิดในเดือนของ billDate — ใช้ตัวคูณฤดูกาลของเดือนนั้น
// (กราฟฤดูกาลสร้างจากยอดออกบิลรายเดือน จึงใช้เดือนของใบแจ้งหนี้)
_Usage _usageForBillMonth(_Options o, List<_Appliance> appliances, DateTime billDate, int index) {
  final key = SeasonalCurves.caseKeyFor(area: o.area, meterType: o.isTou ? 'tou' : 'normal');
  final elecSeason = SeasonalCurves.elec[key]![billDate.month - 1];
  final waterSeason = SeasonalCurves.water[key]![billDate.month - 1];
  final trend = pow(1.02, index / 12).toDouble(); // โตเบาๆ 2%/ปี
  final rng = Random(billDate.year * 100 + billDate.month + o.caseName.hashCode);
  final elecNoise = 1 + (rng.nextDouble() * 0.12 - 0.06); // ±6%
  final waterNoise = 1 + (rng.nextDouble() * 0.10 - 0.05); // ±5%
  final factor = elecSeason * trend * elecNoise;

  double peak = 0, offPeak = 0;
  for (final a in appliances) {
    final kwh = a.monthlyKwh * factor;
    final peakShare = o.isTou ? a.peakFraction : 1.0;
    peak += kwh * peakShare;
    offPeak += kwh * (1 - peakShare);
  }
  final water = (o.isUpcountry ? 15.0 : 18.0) * waterSeason * trend * waterNoise;
  return _Usage(_round1(peak), _round1(offPeak), _round1(water));
}

double _round1(double v) => double.parse(v.toStringAsFixed(1));
double _round2(double v) => double.parse(v.toStringAsFixed(2));

// วันที่บันทึกมิเตอร์ภายในรอบ: กระจายตลอดรอบ ครั้งสุดท้ายคือวันก่อนวันตัดรอบ
// (วันตัดรอบเป็นของรอบถัดไป) รอบปัจจุบันบันทึกถึงเมื่อวานเท่านั้น
List<DateTime> _readingDates(DateTime start, DateTime lastDay, int count, Random rng) {
  final span = lastDay.difference(start).inDays;
  if (span <= 0) return [];
  final n = min(count, span);
  final dates = <DateTime>[];
  for (var i = 1; i <= n; i++) {
    var day = (span * i / n).round();
    if (i < n) day = max(1, day - rng.nextInt(2));
    final d = start.add(Duration(days: day));
    if (dates.isEmpty || d.isAfter(dates.last)) dates.add(d.add(const Duration(hours: 20)));
  }
  return dates;
}

// ==================== สร้างเอกสาร Firestore ====================

Map<String, List<Map<String, dynamic>>> _buildDocuments(
    _Plan plan, _Options o, String uid, double ftRate) {
  final bills = <Map<String, dynamic>>[];
  final elecLogs = <Map<String, dynamic>>[];
  final waterLogs = <Map<String, dynamic>>[];
  final startRecords = <Map<String, dynamic>>[];

  var peakMeter = o.isTou ? o.peakStart : o.elecStart; // มิเตอร์ปกติใช้ตัวนี้ตัวเดียว
  var offPeakMeter = o.offPeakStart;
  var waterMeter = o.waterStart;

  double elecCost(double peakUsed, double offPeakUsed) => o.isTou
      ? _electricityTou(peakUsed, offPeakUsed, ftRate)
      : _electricity(peakUsed + offPeakUsed, ftRate);
  double waterCost(double units) => o.isUpcountry ? _waterPwa(units) : _waterMwa(units);

  void addCycle(_Cycle c, {required bool isCurrent}) {
    final startId = '${c.start.year}_${c.start.month.toString().padLeft(2, '0')}';
    startRecords.add({
      'id': 'demo_start_$startId',
      'uid': uid,
      'electricityValue': o.isTou ? 0.0 : _round1(peakMeter),
      'waterValue': _round1(waterMeter),
      'peakValue': o.isTou ? _round1(peakMeter) : 0.0,
      'offPeakValue': o.isTou ? _round1(offPeakMeter) : 0.0,
      'billingMonth': c.start.month,
      'billingYear': c.start.year,
      'recordedAt': c.start.add(const Duration(hours: 9)).toIso8601String(),
    });

    final rng = Random(c.start.year * 100 + c.start.month);
    final today = DateTime.now();
    final lastDay = isCurrent
        ? DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1))
        : c.end.subtract(const Duration(days: 1));
    final dates = _readingDates(c.start, lastDay, 4 + rng.nextInt(2), rng);
    final cycleDays = c.end.difference(c.start).inDays;

    double prevPeak = 0, prevOff = 0, prevWater = 0;
    for (var i = 0; i < dates.length; i++) {
      final isLastClosed = !isCurrent && i == dates.length - 1;
      // สัดส่วนการใช้ ณ วันที่บันทึก ตามจำนวนวันที่ผ่านไป (+ผันผวนเล็กน้อย)
      final progress = isLastClosed
          ? 1.0
          : min(0.99, dates[i].difference(c.start).inHours / 24 / cycleDays *
              (0.95 + rng.nextDouble() * 0.1));
      final peakUsed = _round1(max(prevPeak, c.usage.peakKwh * progress));
      final offUsed = _round1(max(prevOff, c.usage.offPeakKwh * progress));
      final waterUsed = _round1(max(prevWater, c.usage.waterUnits * progress));
      final id = 'demo_${startId}_${i + 1}';
      final usedFromStart = _round1(peakUsed + offUsed);
      elecLogs.add({
        'id': id,
        'uid': uid,
        'date': dates[i].toIso8601String(),
        // มิเตอร์ปกติเก็บเลขมิเตอร์ / TOU เก็บหน่วยที่ใช้จากต้นรอบ (เหมือนแอป)
        'meterValue': o.isTou ? usedFromStart : _round1(peakMeter + peakUsed),
        'peakMeterValue': o.isTou ? _round1(peakMeter + peakUsed) : null,
        'offPeakMeterValue': o.isTou ? _round1(offPeakMeter + offUsed) : null,
        'usedFromStart': usedFromStart,
        'usedFromLast': _round2(peakUsed - prevPeak + offUsed - prevOff),
        'cost': elecCost(peakUsed, offUsed),
      });
      waterLogs.add({
        'id': id,
        'uid': uid,
        'date': dates[i].toIso8601String(),
        'meterValue': _round1(waterMeter + waterUsed),
        'usedFromStart': waterUsed,
        'usedFromLast': _round2(waterUsed - prevWater),
        'cost': waterCost(waterUsed),
      });
      prevPeak = peakUsed;
      prevOff = offUsed;
      prevWater = waterUsed;
    }

    if (isCurrent) return;
    final eCost = elecCost(c.usage.peakKwh, c.usage.offPeakKwh);
    final wCost = waterCost(c.usage.waterUnits);
    bills.add({
      'id': 'compiled_${c.end.year}_${c.end.month.toString().padLeft(2, '0')}',
      'uid': uid,
      'year': c.end.year,
      'month': c.end.month,
      'yearMonth': c.end.year * 100 + c.end.month,
      'electricityUsed': c.usage.totalKwh,
      'electricityPeakUsed': o.isTou ? c.usage.peakKwh : 0.0,
      'electricityOffPeakUsed': o.isTou ? c.usage.offPeakKwh : 0.0,
      'waterUsed': c.usage.waterUnits,
      'electricityCost': eCost,
      'waterCost': wCost,
      'fixedCost': 0.0,
      'totalCost': _round2(eCost + wCost),
      'source': 'compiled',
    });
    peakMeter += c.usage.peakKwh;
    offPeakMeter += c.usage.offPeakKwh;
    waterMeter += c.usage.waterUnits;
  }

  for (final c in plan.closedCycles) {
    addCycle(c, isCurrent: false);
  }
  _currentStartValues = (_round1(peakMeter), _round1(offPeakMeter), _round1(waterMeter));
  addCycle(plan.currentCycle, isCurrent: true);

  final appliances = [
    for (var i = 0; i < plan.appliances.length; i++)
      {
        'id': 'demo_appliance_${i + 1}',
        'uid': uid,
        'name': plan.appliances[i].name,
        'watt': plan.appliances[i].watt,
        'iconKey': plan.appliances[i].iconKey,
        'schedules': [
          for (final s in plan.appliances[i].schedules)
            {'days': s.days, 'startTime': '00:00', 'endTime': _hoursToTime(s.hoursPerDay)},
        ],
      },
  ];

  return {
    'bills': bills,
    'electricity_logs': elecLogs,
    'water_logs': waterLogs,
    'start_meter_history': startRecords,
    'appliances': appliances,
  };
}

// เลขต้นรอบของรอบปัจจุบัน (peak/ปกติ, off-peak, น้ำ) — ตั้งตอนสร้างเอกสาร
(double, double, double) _currentStartValues = (0, 0, 0);

Map<String, dynamic> _userUpdate(_Plan plan, _Options o) {
  final (peakOrNormal, offPeak, water) = _currentStartValues;
  return {
    'area': o.area,
    'meterType': o.isTou ? 'tou' : 'normal',
    'billingDay': o.billingDay,
    'billingDayConfigured': true,
    'fixedCost': 0.0,
    'startElectricityValue': o.isTou ? 0.0 : peakOrNormal,
    'startPeakValue': o.isTou ? peakOrNormal : 0.0,
    'startOffPeakValue': o.isTou ? offPeak : 0.0,
    'startWaterValue': water,
    'startBillingMonth': plan.currentCycle.start.month,
    'startBillingYear': plan.currentCycle.start.year,
    'startMeterConfigured': true,
    'electricityStartConfigured': true,
    'waterStartConfigured': true,
  };
}

// ตรวจกติกาที่แอปต้องการ: บันทึกมิเตอร์อยู่ในรอบ [start, end) ของตัวเองและไม่เกิน
// วันนี้, เลขมิเตอร์สะสมไม่ลดลง, หน่วยที่ใช้จากครั้งก่อนไม่ติดลบ
List<String> _validate(
    Map<String, List<Map<String, dynamic>>> docs, _Plan plan, DateTime now) {
  final problems = <String>[];
  final cycles = [...plan.closedCycles, plan.currentCycle];
  for (final kind in ['electricity_logs', 'water_logs']) {
    double lastMeter = -1;
    for (final log in docs[kind]!) {
      final date = DateTime.parse(log['date'] as String);
      final inCycle = cycles.any((c) => !date.isBefore(c.start) && date.isBefore(c.end));
      if (!inCycle) problems.add('$kind ${log['id']} วันที่ไม่อยู่ในรอบใดเลย');
      if (date.isAfter(now)) problems.add('$kind ${log['id']} วันที่เลยวันนี้');
      if ((log['usedFromLast'] as double) < 0) problems.add('$kind ${log['id']} ใช้ติดลบ');
      final meter = (log['peakMeterValue'] as double?) ?? (log['meterValue'] as double);
      if (meter < lastMeter) problems.add('$kind ${log['id']} เลขมิเตอร์ลดลง');
      lastMeter = meter;
    }
  }
  return problems;
}

String _hoursToTime(double hours) {
  final h = hours.floor();
  final m = ((hours - h) * 60).round();
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

void _printPreview(_Options o, _Plan plan) {
  print('=== ข้อมูลเดโม ${o.caseName} (${o.apply ? 'APPLY' : 'DRY-RUN'}) ===');
  print('วันตัดรอบ: ${o.billingDay} | รอบปัจจุบันเริ่ม ${_date(plan.currentCycle.start)}');
  print('\nบิลที่ปิดรอบแล้ว ${plan.closedCycles.length} เดือน (หน่วยไฟ / น้ำ):');
  for (final c in plan.closedCycles) {
    final split = o.isTou
        ? ' (On ${c.usage.peakKwh.toStringAsFixed(0)} / Off ${c.usage.offPeakKwh.toStringAsFixed(0)})'
        : '';
    print('  ${c.end.year}-${c.end.month.toString().padLeft(2, '0')}  '
        '${c.usage.totalKwh.toStringAsFixed(0)} หน่วย$split / '
        '${c.usage.waterUnits.toStringAsFixed(1)} ลบ.ม.');
  }
  print('\nอุปกรณ์ ${plan.appliances.length} ชิ้น: '
      '${plan.appliances.map((a) => a.name).join(', ')}');
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ==================== อุปกรณ์ในบ้าน ====================

class _Schedule {
  const _Schedule(this.days, this.hoursPerDay);
  final List<int> days; // 0 = จันทร์ ... 6 = อาทิตย์
  final double hoursPerDay;
}

class _Appliance {
  const _Appliance(this.name, this.iconKey, this.watt, this.schedules,
      {this.dutyFactor = 1.0, required this.peakFraction});
  final String name;
  final String? iconKey; // key เดียวกับ DefaultAppliance.icon ในแอป
  final double watt;
  final List<_Schedule> schedules;
  final double dutyFactor; // แอร์ไม่ได้ทำงานเต็มกำลังตลอด (คอมเพรสเซอร์ตัด-ต่อ)
  final double peakFraction; // สัดส่วนการใช้ที่ตกช่วง On-Peak (จ.-ศ. 09:00-22:00)

  // kWh เฉลี่ยต่อเดือน (30.4 วัน) ก่อนปรับฤดูกาล
  double get monthlyKwh {
    final weeklyHours = schedules.fold<double>(0, (s, x) => s + x.hoursPerDay * x.days.length);
    return watt / 1000 * weeklyHours * dutyFactor * 30.4 / 7;
  }
}

const _all = [0, 1, 2, 3, 4, 5, 6];
const _weekdays = [0, 1, 2, 3, 4];
const _weekend = [5, 6];

List<_Appliance> _appliancesFor(bool isUpcountry) => isUpcountry
    ? const [
        _Appliance('ตู้เย็น', 'kitchen', 100, [_Schedule(_all, 24)], peakFraction: 0.39),
        _Appliance('เครื่องปรับอากาศ (Inverter)', 'ac_unit', 800, [_Schedule(_all, 6)],
            dutyFactor: 0.35, peakFraction: 0.0),
        _Appliance('เครื่องปรับอากาศ (Fixed Speed)', 'ac_unit', 1000,
            [_Schedule(_weekdays, 3), _Schedule(_weekend, 4)],
            dutyFactor: 0.35, peakFraction: 0.65),
        _Appliance('เครื่องทำน้ำอุ่นไฟฟ้า', 'shower', 4000, [_Schedule(_all, 1.0)],
            peakFraction: 0.36),
        _Appliance('หม้อหุงข้าวไฟฟ้า', 'rice_bowl', 600, [_Schedule(_all, 1)], peakFraction: 0.71),
        _Appliance('พัดลมไฟฟ้า', 'mode_fan_off', 50,
            [_Schedule(_weekdays, 5), _Schedule(_weekend, 6)], peakFraction: 0.68),
        _Appliance('เครื่องซักผ้า', 'local_laundry_service', 500, [_Schedule(_weekend, 1)],
            peakFraction: 0.0),
        _Appliance('เตารีดไฟฟ้า', 'iron', 1200, [_Schedule([2], 1)], peakFraction: 0.5),
      ]
    : const [
        _Appliance('ตู้เย็น', 'kitchen', 100, [_Schedule(_all, 24)], peakFraction: 0.39),
        _Appliance('เครื่องปรับอากาศ (Inverter)', 'ac_unit', 900, [_Schedule(_all, 8)],
            dutyFactor: 0.4, peakFraction: 0.0),
        _Appliance('เครื่องปรับอากาศ (Inverter) ห้องลูก', 'ac_unit', 750, [_Schedule(_all, 5)],
            dutyFactor: 0.35, peakFraction: 0.0),
        _Appliance('เครื่องปรับอากาศ (Fixed Speed)', 'ac_unit', 1200,
            [_Schedule(_weekdays, 4), _Schedule(_weekend, 5)],
            dutyFactor: 0.4, peakFraction: 0.67),
        _Appliance('เครื่องทำน้ำอุ่นไฟฟ้า', 'shower', 4500, [_Schedule(_all, 1.2)],
            peakFraction: 0.36),
        _Appliance('หม้อหุงข้าวไฟฟ้า', 'rice_bowl', 600, [_Schedule(_all, 1)], peakFraction: 0.71),
        _Appliance('เตาไมโครเวฟ', 'microwave', 1200, [_Schedule(_all, 0.25)], peakFraction: 0.71),
        _Appliance('พัดลมไฟฟ้า', 'mode_fan_off', 50,
            [_Schedule(_weekdays, 4), _Schedule(_weekend, 5)], peakFraction: 0.67),
        _Appliance('เครื่องซักผ้า', 'local_laundry_service', 500, [_Schedule(_weekend, 1)],
            peakFraction: 0.0),
        _Appliance('เตารีดไฟฟ้า', 'iron', 1200, [_Schedule([2], 1)], peakFraction: 0.5),
      ];

// ==================== อัตราค่าไฟ/ค่าน้ำ (คัดลอกจาก lib/utils/calculator.dart) ====================

const _vat = 1.07;
const _serviceFee = 24.62;

double _electricity(double units, double ft) {
  if (units <= 0) return 0;
  double energy;
  if (units <= 150) {
    energy = units * 3.2484;
  } else if (units <= 400) {
    energy = 150 * 3.2484 + (units - 150) * 4.2218;
  } else {
    energy = 150 * 3.2484 + 250 * 4.2218 + (units - 400) * 4.4217;
  }
  return _round2((energy + _serviceFee + units * ft) * _vat);
}

double _electricityTou(double peak, double offPeak, double ft) {
  if (peak <= 0 && offPeak <= 0) return 0;
  final energy = peak * 5.7982 + offPeak * 2.6369;
  return _round2((energy + _serviceFee + (peak + offPeak) * ft) * _vat);
}

// ขั้นบันได [หน่วยสูงสุดของขั้น, ราคาต่อหน่วย]
double _tiered(double units, List<List<double>> tiers) {
  double cost = 0, previous = 0;
  for (final t in tiers) {
    if (units <= previous) break;
    cost += (min(units, t[0]) - previous) * t[1];
    previous = t[0];
  }
  return cost;
}

double _waterMwa(double units) {
  if (units <= 0) return 0;
  final cost = _tiered(units, const [
    [30, 8.50], [40, 10.03], [50, 10.35], [60, 10.68], [70, 11.00], [80, 11.33],
    [90, 12.50], [100, 12.82], [120, 13.15], [160, 13.47], [200, 13.80], [double.infinity, 14.45],
  ]);
  final subtotal = cost + 25.0 + units * 0.15; // ที่พักอาศัยไม่มีค่าน้ำขั้นต่ำ
  return _round2(subtotal * _vat);
}

double _waterPwa(double units) {
  if (units <= 0) return 0;
  final cost = _tiered(units, const [
    [10, 10.20], [20, 16.00], [30, 19.00], [50, 21.20], [80, 21.60], [100, 21.65],
    [300, 21.70], [1000, 21.75], [2000, 21.80], [3000, 21.85], [double.infinity, 21.90],
  ]);
  final subtotal = cost + 30.0; // ที่อยู่อาศัยไม่มีค่าน้ำขั้นต่ำ
  return _round2(subtotal * _vat);
}

Future<double> _getFtRate(_FirestoreRestClient firestore) async {
  try {
    final doc = await firestore.getDocument('app_config/electricity_rates');
    final ft = doc?['fields']?['ft_rate'];
    final value = ft?['doubleValue'] ?? ft?['integerValue'];
    return value == null ? 0.1623 : double.parse(value.toString());
  } catch (_) {
    return 0.1623;
  }
}

// ==================== Firebase REST ====================

Future<Map<String, dynamic>> _signIn(
    HttpClient client, String apiKey, String email, String password) async {
  final request = await client.postUrl(Uri.parse('$_identityToolkitUrl?key=$apiKey'));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'email': email, 'password': password, 'returnSecureToken': true}));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw Exception('sign-in ล้มเหลว (${response.statusCode}) — ตรวจว่าสมัครบัญชีนี้ในแอปแล้ว: $body');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

class _FirestoreRestClient {
  _FirestoreRestClient(this.client, this.projectId, this.idToken);
  final HttpClient client;
  final String projectId;
  final String idToken;

  String get _root => 'https://firestore.googleapis.com/v1';
  String get _base => '$_root/projects/$projectId/databases/(default)/documents';

  Future<String> _send(HttpClientRequest request, String what, {Object? body}) async {
    request.headers.set('Authorization', 'Bearer $idToken');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return '';
    if (response.statusCode != 200) {
      throw Exception('$what ล้มเหลว (${response.statusCode}): $text');
    }
    return text;
  }

  Future<Map<String, dynamic>?> getDocument(String path) async {
    final text = await _send(await client.getUrl(Uri.parse('$_base/$path')), 'อ่าน $path');
    return text.isEmpty ? null : jsonDecode(text) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listDocuments(String collectionPath) async {
    final docs = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final uri = Uri.parse('$_base/$collectionPath').replace(queryParameters: {
        'pageSize': '300',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final text = await _send(await client.getUrl(uri), 'อ่าน $collectionPath');
      if (text.isEmpty) break;
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      docs.addAll(((decoded['documents'] as List?) ?? []).cast<Map<String, dynamic>>());
      pageToken = decoded['nextPageToken'] as String?;
    } while (pageToken != null);
    return docs;
  }

  // name = ชื่อเต็มที่ได้จาก listDocuments (projects/.../documents/...)
  Future<void> deleteDocument(String name) async {
    await _send(await client.deleteUrl(Uri.parse('$_root/$name')), 'ลบ $name');
  }

  // เขียนเฉพาะฟิลด์ที่ส่งมา (updateMask) — เอกสารที่ยังไม่มีจะถูกสร้างใหม่
  Future<void> patchDocument(String path, Map<String, dynamic> fields) async {
    final mask = fields.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
    await _send(await client.patchUrl(Uri.parse('$_base/$path?$mask')), 'เขียน $path',
        body: {'fields': fields.map((k, v) => MapEntry(k, _encode(v)))});
  }
}

Map<String, dynamic> _encode(dynamic v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is double) return {'doubleValue': v};
  if (v is String) return {'stringValue': v};
  if (v is List) return {'arrayValue': {'values': v.map(_encode).toList()}};
  if (v is Map) {
    return {'mapValue': {'fields': v.map((k, x) => MapEntry(k.toString(), _encode(x)))}};
  }
  throw ArgumentError('ไม่รู้จักชนิดข้อมูล ${v.runtimeType}');
}

// ==================== ตัวเลือกคำสั่ง ====================

class _Options {
  _Options(this.values);
  final Map<String, String> values;

  String get caseName => values['case']!;
  bool get isUpcountry => caseName.startsWith('upcountry');
  bool get isTou => caseName.endsWith('_tou');
  String get area => isUpcountry ? 'province' : 'bangkok';
  String get projectId => values['project-id']!;
  String get apiKey => values['api-key']!;
  String get email => values['email']!;
  late final String password = values['password'] ?? _askPassword(email);
  int get billingDay => int.parse(values['billing-day'] ?? '30');
  int get months => int.parse(values['months'] ?? '24');
  double get elecStart => double.parse(values['elec-start'] ?? '12000');
  double get peakStart => double.parse(values['peak-start'] ?? '5000');
  double get offPeakStart => double.parse(values['off-peak-start'] ?? '8000');
  double get waterStart => double.parse(values['water-start'] ?? '800');
  bool get apply => values.containsKey('apply');
  bool get reset => values.containsKey('reset');
  bool get skipConfirm => values.containsKey('yes');
}

const _cases = ['bangkok_normal', 'bangkok_tou', 'upcountry_normal', 'upcountry_tou'];

_Options? _parseArgs(List<String> args) {
  final values = <String, String>{};
  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      _printHelp();
      return null;
    }
    if (!arg.startsWith('--')) {
      stderr.writeln('ไม่รู้จัก argument: $arg');
      exitCode = 1;
      return null;
    }
    final eq = arg.indexOf('=');
    values[eq < 0 ? arg.substring(2) : arg.substring(2, eq)] = eq < 0 ? '' : arg.substring(eq + 1);
  }
  final missing = ['case', 'project-id', 'api-key', 'email'].where((k) => !values.containsKey(k));
  if (missing.isNotEmpty || !_cases.contains(values['case'])) {
    stderr.writeln(missing.isNotEmpty
        ? 'ขาด argument: ${missing.map((k) => '--$k').join(', ')}\n'
        : '--case ต้องเป็นหนึ่งใน: ${_cases.join(', ')}\n');
    _printHelp();
    exitCode = 1;
    return null;
  }
  final billingDay = int.tryParse(values['billing-day'] ?? '30');
  if (billingDay == null || billingDay < 1 || billingDay > 31) {
    stderr.writeln('--billing-day ต้องเป็นตัวเลข 1-31');
    exitCode = 1;
    return null;
  }
  return _Options(values);
}

String _askPassword(String email) {
  stdout.write('รหัสผ่านของ $email: ');
  try {
    stdin.echoMode = false;
  } catch (_) {}
  final password = stdin.readLineSync() ?? '';
  try {
    stdin.echoMode = true;
  } catch (_) {}
  stdout.writeln();
  return password;
}

void _printHelp() {
  print('''
วิธีใช้:
  dart run tool/demo_data/generate_demo_account.dart --case=CASE \\
    --project-id=ID --api-key=KEY --email=EMAIL [ตัวเลือก]

จำเป็น:
  --case=CASE          bangkok_normal | bangkok_tou | upcountry_normal | upcountry_tou
  --project-id=ID      Firebase project ID
  --api-key=KEY        Firebase Web API Key
  --email=EMAIL        อีเมลของบัญชีที่สมัครไว้แล้ว

ตัวเลือก:
  --password=PASS      ไม่ใส่จะถามแบบซ่อนตัวอักษร
  --billing-day=N      วันตัดรอบบิล 1-31 (ค่าเริ่มต้น 30)
  --months=N           จำนวนบิลย้อนหลัง (ค่าเริ่มต้น 24)
  --elec-start=N       เลขมิเตอร์ไฟเริ่มต้น (มิเตอร์ปกติ, ค่าเริ่มต้น 12000)
  --peak-start=N       เลขมิเตอร์ On-Peak เริ่มต้น (TOU, ค่าเริ่มต้น 5000)
  --off-peak-start=N   เลขมิเตอร์ Off-Peak เริ่มต้น (TOU, ค่าเริ่มต้น 8000)
  --water-start=N      เลขมิเตอร์น้ำเริ่มต้น (ค่าเริ่มต้น 800)
  --reset              ล้างข้อมูลเดิมของบัญชีทั้งหมดก่อนเขียน (รันซ้ำบัญชีเดิม)
  --apply              เขียนข้อมูลจริง (ไม่ใส่ = dry-run ดูตัวอย่างอย่างเดียว)
  --yes                ไม่ต้องถามยืนยันก่อนเขียน
''');
}
