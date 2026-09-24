// tool/forecast_synth/import_case_logs.dart
//
// สคริปต์คู่กับ import_case_bills.dart — ใช้เติม "ประวัติการกรอกมิเตอร์
// รายเดือน" (electricity_logs / water_logs ที่หน้า settings_utility_log.dart
// แสดง) ให้ตรงกับบิลที่ import ไปแล้ว พร้อมทั้งตั้งค่า billingDay ให้บัญชี
// (เผื่อลืมตั้งตอนสมัคร) และอัปเดต startElectricityValue/startWaterValue
// ของบัญชีให้ต่อเนื่องจากประวัติที่เพิ่งสร้าง
//
// สมมติฐาน (เพราะ CSV มีแค่หน่วยใช้ต่อเดือน ไม่มีเลขมิเตอร์สะสมจริง):
//   - จำนวนครั้งที่กรอกต่อเดือนกำหนดได้ผ่าน --readings-min / --readings-max
//     (default 1,1 = กรอกครั้งเดียวตอนตัดรอบ) ถ้าตั้งมากกว่า 1 สคริปต์จะสุ่ม
//     (แบบ deterministic ด้วย seed ตาม ปี/เดือน — รันซ้ำได้ผลเดิมเป๊ะ) ทั้ง
//     "วันที่กรอกภายในรอบ" และ "สัดส่วนหน่วยที่ใช้ในแต่ละครั้ง" โดยยึดว่า
//     หน่วยสะสมต้องเพิ่มขึ้นเรื่อยๆ ภายในรอบ และรวมกันเท่ากับหน่วยทั้งเดือน
//     พอดี (ครั้งสุดท้ายของรอบ = วันตัดรอบ ตรงกับบิลที่ import ไปแล้ว)
//     usedFromStart ของแต่ละครั้ง = สะสมจากต้นรอบถึงครั้งนั้น (เหมือนแอปจริง
//     ที่คำนวณค่าไฟ/น้ำประมาณการจากยอดสะสมทั้งรอบ ไม่ใช่แค่ครั้งล่าสุด)
//     usedFromLast = ส่วนต่างจากครั้งก่อนหน้าในรอบเดียวกัน
//   - เลขมิเตอร์สะสมเริ่มต้นที่ --elec-start / --water-start (default 0)
//     แล้วบวกสะสมไปเรื่อยๆ ทีละเดือนตาม CSV (เลขจะไม่ตรงมิเตอร์จริงถ้ามี
//     แต่ตัวเลข "หน่วยที่ใช้" และ "ค่าใช้จ่าย" ถูกต้องตรงกับบิลเป๊ะ)
//   - หลัง import เสร็จ จะอัปเดต user.startElectricityValue/startWaterValue
//     เป็นเลขมิเตอร์สะสมล่าสุด (ต้นรอบถัดไป) และ startBillingMonth/Year
//     เป็นเดือนถัดจากเดือนสุดท้ายที่ import ให้อัตโนมัติ เพื่อให้หน้า
//     "บันทึกมิเตอร์" ในแอปทำงานต่อได้ปกติจากจุดที่ประวัติจบ
//
// สูตรคำนวณค่าไฟ/น้ำและ safeBillingDate คัดลอกมาจาก
// lib/utils/calculator.dart และ lib/utils/forecaster.dart ต้องตรงกันเป๊ะ
// ถ้าแก้สูตรในแอป อย่าลืมแก้ที่นี่ด้วย (เหตุผลเดียวกับ import_case_bills.dart)
//
// วิธีใช้ (dry-run ก่อนเสมอ แล้วค่อย --apply):
//
//   dart run tool/forecast_synth/import_case_logs.dart \
//     --project-id=YOUR_PROJECT_ID \
//     --api-key=YOUR_FIREBASE_WEB_API_KEY \
//     --email=user@example.com \
//     --csv=tool/forecast_synth/case1_bangkok_normal.csv \
//     --household=case1_0000 \
//     --billing-day=5 \
//     --area=bangkok
//
//   ตัวเลือกเสริม: --elec-start=1000 --water-start=100 (เลขมิเตอร์สะสมตั้งต้น)
//                  --readings-min=5 --readings-max=6 (กรอกกี่ครั้ง/เดือน)

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _identityToolkitUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';

void main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) return;

  stdout.writeln(
      '=== Import meter-reading logs (${options.apply ? "APPLY" : "DRY-RUN"} mode) ===');

  // ---------- 1) อ่าน + กรอง CSV (เหมือน import_case_bills.dart) ----------
  final csvFile = File(options.csvPath);
  if (!csvFile.existsSync()) {
    stderr.writeln('ไม่พบไฟล์ CSV: ${options.csvPath}');
    exitCode = 1;
    return;
  }
  final lines =
      csvFile.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  final header = lines.first.split(',').map((h) => h.trim()).toList();
  final isTou = header.contains('elec_units_onpeak');

  final rows = <_Row>[];
  for (final line in lines.skip(1)) {
    final cols = line.split(',');
    final rowMap = <String, String>{};
    for (var i = 0; i < header.length && i < cols.length; i++) {
      rowMap[header[i]] = cols[i].trim();
    }
    if (rowMap['household_id'] != options.household) continue;
    rows.add(_Row(
      year: int.parse(rowMap['year']!),
      month: int.parse(rowMap['month']!),
      elecUnits: isTou ? 0 : double.parse(rowMap['elec_units']!),
      elecPeakUnits: isTou ? double.parse(rowMap['elec_units_onpeak']!) : 0,
      elecOffPeakUnits:
          isTou ? double.parse(rowMap['elec_units_offpeak']!) : 0,
      waterUnits: double.parse(rowMap['water_units']!),
    ));
  }
  rows.sort((a, b) => (a.year * 12 + a.month).compareTo(b.year * 12 + b.month));

  if (rows.isEmpty) {
    stderr.writeln(
        'ไม่พบแถวไหนที่ household_id == "${options.household}" ใน ${options.csvPath}');
    exitCode = 1;
    return;
  }

  if (options.extendToCurrent) {
    final before = rows.length;
    _extendToCurrentMonth(rows, isTou);
    if (rows.length > before) {
      final now = DateTime.now();
      stdout.writeln(
          'ขยายข้อมูลเพิ่ม ${rows.length - before} เดือน (ประมาณการจากแนวโน้ม+ฤดูกาลของข้อมูลเดิม) '
          'ถึงเดือนปัจจุบัน ${now.year}-${now.month.toString().padLeft(2, '0')}');
    }
  }

  stdout.writeln(
      'พบ ${rows.length} เดือนสำหรับ household "${options.household}" '
      '(meterType=${isTou ? 'tou' : 'normal'}, billingDay=${options.billingDay})\n');

  final client = HttpClient();
  try {
    // ---------- 2) Sign in ----------
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

    // ---------- 3) สร้าง log + start_meter_history แต่ละเดือน (สะสมเลขมิเตอร์) ----------
    double elecCumulative = options.elecStart;
    double peakCumulative = options.elecStart; // ใช้ elecStart ร่วมกันถ้าเป็น TOU
    double offPeakCumulative = 0;
    double waterCumulative = options.waterStart;

    final electricityLogs = <Map<String, dynamic>>[];
    final waterLogs = <Map<String, dynamic>>[];
    final startMeterRecords = <Map<String, dynamic>>[];

    // วันตัดรอบของ "เดือนก่อนแถวแรกใน CSV" ใช้เป็นจุดเริ่มต้นของรอบแรก
    DateTime previousCutoff = () {
      var prevMonth = rows.first.month - 1;
      var prevYear = rows.first.year;
      if (prevMonth < 1) {
        prevMonth = 12;
        prevYear -= 1;
      }
      return _safeBillingDate(prevYear, prevMonth, options.billingDay);
    }();

    for (final r in rows) {
      final cycleCutoff = _safeBillingDate(r.year, r.month, options.billingDay);
      final cycleStart = previousCutoff.add(const Duration(days: 1));
      final monthId = 'imported_${r.year}_${r.month.toString().padLeft(2, '0')}';

      // ค่าต้นรอบของเดือนนี้ = ค่าสะสมก่อนบวกหน่วยเดือนนี้เข้าไป
      startMeterRecords.add({
        'id': monthId,
        'uid': targetUid,
        'electricityValue': isTou ? 0.0 : elecCumulative,
        'waterValue': waterCumulative,
        'peakValue': isTou ? peakCumulative : 0.0,
        'offPeakValue': isTou ? offPeakCumulative : 0.0,
        'billingMonth': r.month,
        'billingYear': r.year,
        'recordedAt': cycleStart.toIso8601String(),
      });

      final seed = r.year * 100 + r.month;
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
        if (isTou) {
          // ครั้งสุดท้ายบังคับให้เท่ากับยอดทั้งเดือนพอดี กัน error สะสมจาก
          // การปัดเศษของสัดส่วนสุ่ม
          final peakUsed =
              isLast ? r.elecPeakUnits : r.elecPeakUnits * peakFractions[i];
          final offPeakUsed = isLast
              ? r.elecOffPeakUnits
              : r.elecOffPeakUnits * offPeakFractions[i];
          peakCumulative = peakCumulative - prevPeakUsed + peakUsed;
          // ↑ ปรับให้ peakCumulative เดินไปตาม "สะสมจากต้นรอบ" ของครั้งนี้
          //   (prevPeakUsed คือค่าที่เคยบวกไปแล้วจากครั้งก่อนของรอบเดียวกัน)
          peakMeterValue = peakCumulative;
          offPeakCumulative = offPeakCumulative - prevOffPeakUsed + offPeakUsed;
          offPeakMeterValue = offPeakCumulative;
          usedFromStartElec = peakUsed + offPeakUsed;
          usedFromLastElec =
              (peakUsed - prevPeakUsed) + (offPeakUsed - prevOffPeakUsed);
          elecCost = _calculateElectricityTOU(
            peakUnits: peakUsed,
            offPeakUnits: offPeakUsed,
            ftRate: ftRate,
          );
          prevPeakUsed = peakUsed;
          prevOffPeakUsed = offPeakUsed;
        } else {
          final elecUsed =
              isLast ? r.elecUnits : r.elecUnits * elecFractions[i];
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
          'peakMeterValue': isTou ? peakMeterValue : null,
          'offPeakMeterValue': isTou ? offPeakMeterValue : null,
          'usedFromStart': usedFromStartElec,
          'usedFromLast': usedFromLastElec,
          'cost': elecCost,
        });

        final waterUsed =
            isLast ? r.waterUnits : r.waterUnits * waterFractions[i];
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

    // ---------- 4) เตรียม user doc update (billingDay + ต้นรอบถัดไป) ----------
    final lastRow = rows.last;
    var nextMonth = lastRow.month + 1;
    var nextYear = lastRow.year;
    if (nextMonth > 12) {
      nextMonth = 1;
      nextYear += 1;
    }
    final userUpdate = <String, dynamic>{
      'billingDay': options.billingDay,
      'billingDayConfigured': true,
      'meterType': isTou ? 'tou' : 'normal',
      'area': options.area,
      'startElectricityValue': isTou ? 0.0 : elecCumulative,
      'startWaterValue': waterCumulative,
      'startPeakValue': isTou ? peakCumulative : 0.0,
      'startOffPeakValue': isTou ? offPeakCumulative : 0.0,
      'startBillingMonth': nextMonth,
      'startBillingYear': nextYear,
      'startMeterConfigured': true,
      'electricityStartConfigured': true,
      'waterStartConfigured': true,
    };

    // ---------- 5) พิมพ์ preview ----------
    stdout.writeln(
        '--- Preview (${rows.length} เดือน, รวม ${electricityLogs.length} ครั้งที่กรอก) ---');
    for (var i = 0; i < electricityLogs.length; i++) {
      final e = electricityLogs[i];
      final w = waterLogs[i];
      final label = (e['date'] as String).substring(0, 10);
      stdout.writeln('  $label  '
          'ไฟ: มิเตอร์=${(e['meterValue'] as double).toStringAsFixed(1)} '
          '(+${(e['usedFromLast'] as double).toStringAsFixed(1)}) '
          'ค่าไฟสะสม=${(e['cost'] as double).toStringAsFixed(2)}   '
          'น้ำ: มิเตอร์=${(w['meterValue'] as double).toStringAsFixed(1)} '
          '(+${(w['usedFromLast'] as double).toStringAsFixed(1)}) '
          'ค่าน้ำสะสม=${(w['cost'] as double).toStringAsFixed(2)}');
    }
    stdout.writeln('\nหลัง import: billingDay=${options.billingDay}, '
        'ต้นรอบถัดไป=$nextYear-${nextMonth.toString().padLeft(2, '0')}, '
        'เลขมิเตอร์ต้นรอบถัดไป ไฟ=${(userUpdate['startElectricityValue'] as double).toStringAsFixed(1)} '
        'น้ำ=${(userUpdate['startWaterValue'] as double).toStringAsFixed(1)}\n');

    if (!options.apply) {
      stdout.writeln(
          '(นี่คือ dry-run เฉยๆ ยังไม่มีการเขียนข้อมูลใดๆ — รันซ้ำพร้อม --apply เมื่อพร้อม)');
      return;
    }

    if (!options.skipConfirm) {
      stdout.write(
          'กำลังจะเขียน ${electricityLogs.length} ครั้งที่กรอก (electricity_logs + '
          'water_logs) และ ${startMeterRecords.length} รอบบิล (start_meter_history) '
          'และอัปเดต billingDay/ต้นรอบของ users/$targetUid — '
          'พิมพ์ "yes" เพื่อยืนยัน: ');
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

    for (final log in electricityLogs) {
      await write('users/$targetUid/electricity_logs', log);
    }
    for (final log in waterLogs) {
      await write('users/$targetUid/water_logs', log);
    }
    for (final rec in startMeterRecords) {
      await write('users/$targetUid/start_meter_history', rec);
    }
    try {
      await firestore.patchDocumentFields('users/$targetUid', userUpdate);
      success++;
      stdout.writeln('  ✅ users/$targetUid อัปเดต billingDay/ต้นรอบแล้ว');
    } catch (e) {
      failed++;
      stderr.writeln('  ❌ users/$targetUid อัปเดตล้มเหลว: $e');
    }

    stdout.writeln('\nเสร็จสิ้น: สำเร็จ $success รายการ, ล้มเหลว $failed รายการ');
  } finally {
    client.close(force: true);
  }
}

class _Row {
  final int year;
  final int month;
  final double elecUnits;
  final double elecPeakUnits;
  final double elecOffPeakUnits;
  final double waterUnits;

  _Row({
    required this.year,
    required this.month,
    required this.elecUnits,
    required this.elecPeakUnits,
    required this.elecOffPeakUnits,
    required this.waterUnits,
  });
}

// ==================== ขยายข้อมูลถึงเดือนปัจจุบัน (ตอน --extend-to-current) ====================
// เหมือนกับใน import_case_bills.dart เป๊ะ — ต้องให้สองสคริปต์ประมาณการ
// เดือนเดียวกันได้ค่าตรงกัน (ทั้งคู่ deterministic จาก seed เดียวกัน) บิลกับ
// log ของเดือนที่ขยายเพิ่มถึงจะสอดคล้องกัน
void _extendToCurrentMonth(List<_Row> rows, bool isTou) {
  if (rows.isEmpty) return;
  final now = DateTime.now();

  _Row? findRow(int year, int month) {
    for (final r in rows) {
      if (r.year == year && r.month == month) return r;
    }
    return null;
  }

  double growthFactor(double Function(_Row) selector) {
    final recentWindow =
        rows.length >= 3 ? rows.sublist(rows.length - 3) : rows;
    double recentSum = 0, pastSum = 0;
    for (final r in recentWindow) {
      final past = findRow(r.year - 1, r.month);
      recentSum += selector(r);
      pastSum += selector(past ?? r);
    }
    if (pastSum <= 0) return 1.0;
    final ratio = recentSum / pastSum;
    return ratio.clamp(0.8, 1.2);
  }

  while (true) {
    final last = rows.last;
    var nextMonth = last.month + 1;
    var nextYear = last.year;
    if (nextMonth > 12) {
      nextMonth = 1;
      nextYear += 1;
    }
    if (nextYear > now.year || (nextYear == now.year && nextMonth > now.month)) {
      break;
    }

    final anchor = findRow(nextYear - 1, nextMonth) ?? last;
    final elecGrowth = isTou ? 1.0 : growthFactor((r) => r.elecUnits);
    final peakGrowth = isTou ? growthFactor((r) => r.elecPeakUnits) : 1.0;
    final offPeakGrowth = isTou ? growthFactor((r) => r.elecOffPeakUnits) : 1.0;
    final waterGrowth = growthFactor((r) => r.waterUnits);

    final rng = Random(nextYear * 100 + nextMonth);
    double withNoise(double base) {
      final noise = 1 + (rng.nextDouble() * 0.10 - 0.05); // ±5%
      final value = base * noise;
      return double.parse((value < 0 ? 0 : value).toStringAsFixed(1));
    }

    rows.add(_Row(
      year: nextYear,
      month: nextMonth,
      elecUnits: isTou ? 0 : withNoise(anchor.elecUnits * elecGrowth),
      elecPeakUnits:
          isTou ? withNoise(anchor.elecPeakUnits * peakGrowth) : 0,
      elecOffPeakUnits:
          isTou ? withNoise(anchor.elecOffPeakUnits * offPeakGrowth) : 0,
      waterUnits: withNoise(anchor.waterUnits * waterGrowth),
    ));
  }
}

DateTime _safeBillingDate(int year, int month, int billingDay) {
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final safeDay = billingDay > lastDayOfMonth ? lastDayOfMonth : billingDay;
  return DateTime(year, month, safeDay);
}

// แบ่งช่วงวันที่ [start, end] เป็น n จุดเรียงจากน้อยไปมาก จุดสุดท้ายตรงกับ
// end เป๊ะเสมอ (= วันตัดรอบ ให้ตรงกับบิลที่ import ไปแล้ว) จุดก่อนหน้ากระจาย
// แบบ "แบ่งเท่าๆ กัน + สุ่มเยื้องเล็กน้อย" เพื่อไม่ให้ห่างเท่ากันแข็งทื่อ
// เกินไป แต่ยังคงเรียงลำดับกันเสมอ (กันชนกันด้วย toSet() ท้ายสุด)
List<DateTime> _splitDatesAscending(
    DateTime start, DateTime end, int n, Random rng) {
  if (n <= 1) return [end];
  final totalDays = end.difference(start).inDays;
  final safeTotalDays = totalDays < (n - 1) ? (n - 1) : totalDays;
  final result = <DateTime>[];
  for (var i = 0; i < n - 1; i++) {
    final base = (safeTotalDays * (i + 1) / n).floor();
    final jitter = safeTotalDays > n ? rng.nextInt((safeTotalDays / n).ceil()) - (safeTotalDays / n / 2).floor() : 0;
    var offset = base + jitter;
    if (offset < i) offset = i; // กันวันซ้อนกับจุดก่อนหน้า
    if (offset >= safeTotalDays) offset = safeTotalDays - 1;
    result.add(start.add(Duration(days: offset)));
  }
  // กันวันซ้ำ/ไม่เรียง เผื่อ jitter ดันชนกัน
  for (var i = 1; i < result.length; i++) {
    if (!result[i].isAfter(result[i - 1])) {
      result[i] = result[i - 1].add(const Duration(days: 1));
    }
  }
  if (result.isNotEmpty && !end.isAfter(result.last)) {
    // ป้องกันกรณีรอบสั้นมากจน jitter ดันจุดสุดท้ายเลย end ไป
    result[result.length - 1] = end.subtract(const Duration(days: 1));
  }
  result.add(end);
  return result;
}

// สุ่มสัดส่วนสะสมแบบเพิ่มขึ้นเรื่อยๆ n จุด ตั้งแต่ >0 ถึง 1.0 (ใช้คูณกับ
// หน่วยรวมทั้งเดือน เพื่อได้ "สะสมจากต้นรอบ" ของแต่ละครั้งที่กรอก) ค่าสุดท้าย
// (index n-1) ไม่ได้ใช้จริง เพราะครั้งสุดท้ายบังคับ = ยอดทั้งเดือนพอดีเสมอ
// (กันเศษปัดเพี้ยนสะสม) แต่คำนวณไว้ให้ครบเผื่อเรียกใช้ที่อื่น
List<double> _splitIncreasingFractions(int n, Random rng) {
  if (n <= 1) return [1.0];
  final weights =
      List.generate(n, (_) => 0.3 + rng.nextDouble()); // กันน้ำหนักใกล้ 0
  final total = weights.reduce((a, b) => a + b);
  var cumulative = 0.0;
  final fractions = <double>[];
  for (final w in weights) {
    cumulative += w;
    fractions.add(cumulative / total);
  }
  return fractions;
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
  final String projectId;
  final String apiKey;
  final String email;
  final String password;
  final String? uid;
  final String csvPath;
  final String household;
  final String area;
  final int billingDay;
  final double elecStart;
  final double waterStart;
  final int readingsMin;
  final int readingsMax;
  final bool extendToCurrent;
  final bool apply;
  final bool skipConfirm;

  _Options({
    required this.projectId,
    required this.apiKey,
    required this.email,
    required this.password,
    required this.uid,
    required this.csvPath,
    required this.household,
    required this.area,
    required this.billingDay,
    required this.elecStart,
    required this.waterStart,
    required this.readingsMin,
    required this.readingsMax,
    required this.extendToCurrent,
    required this.apply,
    required this.skipConfirm,
  });
}

_Options? _parseArgs(List<String> args) {
  String? projectId, apiKey, email, password, uid, csvPath, household, area;
  int? billingDay;
  double elecStart = 0, waterStart = 0;
  int readingsMin = 1, readingsMax = 1;
  bool extendToCurrent = false;
  bool apply = false, skipConfirm = false;

  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      _printHelp();
      return null;
    } else if (arg == '--apply') {
      apply = true;
    } else if (arg == '--yes') {
      skipConfirm = true;
    } else if (arg == '--extend-to-current') {
      extendToCurrent = true;
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
    } else if (arg.startsWith('--csv=')) {
      csvPath = arg.substring('--csv='.length);
    } else if (arg.startsWith('--household=')) {
      household = arg.substring('--household='.length);
    } else if (arg.startsWith('--area=')) {
      area = arg.substring('--area='.length);
    } else if (arg.startsWith('--billing-day=')) {
      billingDay = int.parse(arg.substring('--billing-day='.length));
    } else if (arg.startsWith('--elec-start=')) {
      elecStart = double.parse(arg.substring('--elec-start='.length));
    } else if (arg.startsWith('--water-start=')) {
      waterStart = double.parse(arg.substring('--water-start='.length));
    } else if (arg.startsWith('--readings-min=')) {
      readingsMin = int.parse(arg.substring('--readings-min='.length));
    } else if (arg.startsWith('--readings-max=')) {
      readingsMax = int.parse(arg.substring('--readings-max='.length));
    } else {
      stderr.writeln('ไม่รู้จัก argument: $arg');
      _printHelp();
      exitCode = 1;
      return null;
    }
  }

  if (projectId == null ||
      apiKey == null ||
      email == null ||
      csvPath == null ||
      household == null ||
      billingDay == null) {
    stderr.writeln(
        'ขาด argument ที่จำเป็น (--project-id, --api-key, --email, --csv, --household, --billing-day)\n');
    _printHelp();
    exitCode = 1;
    return null;
  }
  if (billingDay < 1 || billingDay > 31) {
    stderr.writeln('--billing-day ต้องอยู่ระหว่าง 1-31');
    exitCode = 1;
    return null;
  }
  area ??= 'bangkok';
  if (area != 'bangkok' && area != 'province') {
    stderr.writeln('--area ต้องเป็น "bangkok" หรือ "province" เท่านั้น');
    exitCode = 1;
    return null;
  }
  if (readingsMin < 1 || readingsMax < readingsMin) {
    stderr.writeln(
        '--readings-min ต้อง >= 1 และ --readings-max ต้อง >= --readings-min');
    exitCode = 1;
    return null;
  }

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
    projectId: projectId,
    apiKey: apiKey,
    email: email,
    password: password,
    uid: uid,
    csvPath: csvPath,
    household: household,
    area: area,
    billingDay: billingDay,
    elecStart: elecStart,
    waterStart: waterStart,
    readingsMin: readingsMin,
    readingsMax: readingsMax,
    extendToCurrent: extendToCurrent,
    apply: apply,
    skipConfirm: skipConfirm,
  );
}

void _printHelp() {
  stdout.writeln('''
วิธีใช้:
  dart run tool/forecast_synth/import_case_logs.dart \\
    --project-id=ID --api-key=KEY --email=EMAIL \\
    --csv=PATH --household=ID --billing-day=DAY [options]

Required:
  --project-id=ID       Firebase project ID
  --api-key=KEY         Firebase Web API Key
  --email=EMAIL         อีเมลของบัญชีที่จะเพิ่มประวัติให้
  --csv=PATH            path ของไฟล์ CSV
  --household=ID        household_id ที่จะดึงมาใช้ (ต้องตรงกับที่ import_case_bills.dart ใช้)
  --billing-day=DAY     วันตัดรอบบิล 1-31 (จะถูกตั้งให้บัญชีด้วยตอน apply)

Optional:
  --password=PASSWORD   ถ้าไม่ใส่จะถามแบบซ่อนตัวอักษรตอนรัน
  --uid=UID              เขียนให้ uid อื่นที่ไม่ใช่บัญชีที่ sign-in
  --area=bangkok|province  สูตรค่าน้ำ (default: bangkok = MWA)
  --elec-start=NUMBER    เลขมิเตอร์ไฟสะสมตั้งต้น ก่อนเดือนแรกใน CSV (default: 0)
  --water-start=NUMBER   เลขมิเตอร์น้ำสะสมตั้งต้น ก่อนเดือนแรกใน CSV (default: 0)
  --readings-min=N       จำนวนครั้งที่กรอกต่อเดือน ขั้นต่ำ (default: 1)
  --readings-max=N       จำนวนครั้งที่กรอกต่อเดือน สูงสุด (default: 1, ต้อง >= readings-min)
  --extend-to-current    ประมาณการเพิ่มให้ถึงเดือนปัจจุบัน ถ้า CSV ไม่มีข้อมูลถึงเดือนนี้ (ต้องตรงกับที่ใส่ตอนรัน import_case_bills.dart ด้วย ไม่งั้นข้อมูลจะไม่ตรงกัน)
  --apply                เขียนข้อมูลจริง (ไม่ใส่ = dry-run แสดง preview เฉยๆ)
  --yes                  ข้ามการถามยืนยันตอน apply
  --help                 แสดงข้อความนี้
''');
}