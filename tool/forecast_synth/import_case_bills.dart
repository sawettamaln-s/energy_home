// tool/forecast_synth/import_case_bills.dart
//
// นำเข้าข้อมูลจำลอง (synthetic) จาก tool/forecast_synth/case*.csv เข้า
// Firestore เป็นบิลย้อนหลัง (source: 'imported') สำหรับ household_id เดียว
// ใน case file เดียว — ใช้สร้างข้อมูล demo/ทดสอบย้อนหลัง 2-3 ปีให้บัญชีจริง
//
// รองรับ CSV schema สองแบบ (ตรวจจากหัวคอลัมน์อัตโนมัติ):
//   ปกติ (case1/case3): household_id,case,year,month,elec_units,water_units
//   TOU  (case2/case4): household_id,case,year,month,elec_units_onpeak,elec_units_offpeak,water_units
//
// คำนวณค่าไฟ/ค่าน้ำด้วยสูตรเดียวกับ lib/utils/calculator.dart
// (EnergyCalculator) ทุกจุด — คัดลอกมาไว้ในสคริปต์นี้เพราะไฟล์ต้นฉบับ
// import cloud_firestore ที่ผูกกับ Flutter engine เรียกจาก `dart run`
// ตรงๆ ไม่ได้ (เหตุผลเดียวกับ migrate_tou_bills.dart) — ถ้าแก้สูตรในแอป
// อย่าลืมแก้ไฟล์นี้ให้ตรงกันด้วย
//
// เขียนบิลด้วย doc id แบบตายตัว 'imported_{year}_{month}' (ไม่ใช้ uuid
// แบบที่หน้า settings_bill_history.dart ใช้ตอนกรอกเอง) เพื่อให้รันซ้ำได้
// โดยไม่สร้างบิลซ้ำซ้อน (idempotent เหมือน compileBill())
//
// วิธีใช้ (ค่าเริ่มต้นเป็น dry-run เสมอ — ตรวจ preview ก่อนค่อย --apply):
//
//   dart run tool/forecast_synth/import_case_bills.dart \
//     --project-id=YOUR_PROJECT_ID \
//     --api-key=YOUR_FIREBASE_WEB_API_KEY \
//     --email=user@example.com \
//     --csv=tool/forecast_synth/case1_bangkok_normal.csv \
//     --household=case1_0000 \
//     --area=bangkok
//
//   พอใจกับ preview แล้วค่อยรันซ้ำพร้อม --apply
//
// หมายเหตุ: sign-in ด้วยบัญชีของ user ที่จะเพิ่มบิลให้เอง (หรือใส่ --uid
// ถ้า sign-in ด้วยบัญชี admin ที่ security rules อนุญาตให้เขียนบัญชีอื่นได้)

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _identityToolkitUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';

void main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) return; // _parseArgs พิมพ์ help/error ให้แล้ว

  stdout.writeln(
      '=== Import synthetic bills (${options.apply ? "APPLY" : "DRY-RUN"} mode) ===');

  // ---------- 1) อ่าน + กรอง CSV ----------
  final csvFile = File(options.csvPath);
  if (!csvFile.existsSync()) {
    stderr.writeln('ไม่พบไฟล์ CSV: ${options.csvPath}');
    exitCode = 1;
    return;
  }
  final lines = csvFile
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    stderr.writeln('ไฟล์ CSV ว่างเปล่า');
    exitCode = 1;
    return;
  }
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
      elecPeakUnits:
          isTou ? double.parse(rowMap['elec_units_onpeak']!) : 0,
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
      '(${rows.first.year}-${rows.first.month.toString().padLeft(2, '0')} '
      'ถึง ${rows.last.year}-${rows.last.month.toString().padLeft(2, '0')}, '
      'meterType=${isTou ? 'tou' : 'normal'})\n');

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
    stdout.writeln('sign-in สำเร็จ (signed-in uid: $signedInUid)');
    if (targetUid != signedInUid) {
      stdout.writeln(
          'หมายเหตุ: กำลังเขียนบิลให้ uid อื่น ($targetUid) ต่างจากบัญชีที่ '
          'sign-in — ถ้า security rules ไม่อนุญาต จะเจอ PERMISSION_DENIED');
    }
    stdout.writeln('');

    final firestore = _FirestoreRestClient(
      client: client,
      projectId: options.projectId,
      idToken: idToken,
    );

    // ---------- 3) ดึงอัตรา Ft ปัจจุบันจาก app_config (เหมือนที่แอปใช้จริง) ----------
    final ftRate = await _getFtRate(firestore);
    stdout.writeln('Ft rate ที่ใช้คำนวณ: $ftRate\n');

    // ---------- 4) คำนวณบิลแต่ละเดือน ----------
    final bills = <Map<String, dynamic>>[];
    for (final r in rows) {
      double electricityCost;
      double peakUsed = 0, offPeakUsed = 0, elecUsed = 0;
      if (isTou) {
        peakUsed = r.elecPeakUnits;
        offPeakUsed = r.elecOffPeakUnits;
        // เท่ากับ eLogs.first.usedFromStart ที่แอปจริงคำนวณตอน
        // compileBill() (ดู record_meter_screen.dart: usedFromStart =
        // peakUnits + offPeakUnits) — ถ้าปล่อยเป็น 0 แบบก่อนหน้านี้
        // usedSelector ในหน้าวิเคราะห์ (b) => b.electricityUsed จะได้ 0
        // ทุกเดือน ทำให้ maxY ของกราฟตกไปใช้ fallback 8.0 ทั้งที่แท่งจริง
        // (จาก peak+offpeak stacked) สูงเป็นร้อย กราฟเลยทะลุกรอบ
        elecUsed = peakUsed + offPeakUsed;
        electricityCost = _calculateElectricityTOU(
          peakUnits: peakUsed,
          offPeakUnits: offPeakUsed,
          ftRate: ftRate,
        );
      } else {
        elecUsed = r.elecUnits;
        electricityCost =
            _calculateElectricity(elecUsed, options.area, ftRate);
      }
      final waterCost = options.area == 'bangkok'
          ? _calculateWaterMWA(r.waterUnits)
          : _calculateWaterPWA(r.waterUnits);
      final totalCost = electricityCost + waterCost + options.fixedCost;

      bills.add({
        'id': 'imported_${r.year}_${r.month.toString().padLeft(2, '0')}',
        'uid': targetUid,
        'year': r.year,
        'month': r.month,
        'yearMonth': r.year * 100 + r.month,
        'electricityUsed': elecUsed,
        'electricityPeakUsed': peakUsed,
        'electricityOffPeakUsed': offPeakUsed,
        'waterUsed': r.waterUnits,
        'electricityCost': electricityCost,
        'waterCost': waterCost,
        'fixedCost': options.fixedCost,
        'totalCost': totalCost,
        'forecastElectricity': electricityCost,
        'forecastWater': waterCost,
        'forecastTotal': totalCost,
        'source': 'imported',
      });
    }

    // ---------- 5) พิมพ์ preview ----------
    stdout.writeln('--- Preview (${bills.length} บิล) ---');
    for (final b in bills) {
      final label =
          '${b['year']}-${(b['month'] as int).toString().padLeft(2, '0')}';
      stdout.writeln('  $label  '
          'ไฟ ${(b['electricityCost'] as double).toStringAsFixed(2)} บ. + '
          'น้ำ ${(b['waterCost'] as double).toStringAsFixed(2)} บ. '
          '= ${(b['totalCost'] as double).toStringAsFixed(2)} บ. '
          '(doc id: ${b['id']})');
    }
    stdout.writeln('');

    if (!options.apply) {
      stdout.writeln(
          '(นี่คือ dry-run เฉยๆ ยังไม่มีการเขียนข้อมูลใดๆ — รันซ้ำพร้อม --apply เมื่อพร้อม)');
      return;
    }

    // ---------- 6) ยืนยันก่อนเขียนจริง ----------
    if (!options.skipConfirm) {
      stdout.write(
          'กำลังจะเขียน ${bills.length} บิลลง users/$targetUid/bills — '
          'พิมพ์ "yes" เพื่อยืนยัน: ');
      final answer = stdin.readLineSync()?.trim().toLowerCase();
      if (answer != 'yes') {
        stdout.writeln('ยกเลิก ไม่มีการเขียนข้อมูลใดๆ');
        return;
      }
    }

    stdout.writeln('\nกำลัง apply ...');
    var success = 0, failed = 0;
    for (final b in bills) {
      final id = b['id'] as String;
      final fields = Map<String, dynamic>.from(b)..remove('id');
      try {
        await firestore.patchDocumentFields(
            'users/$targetUid/bills/$id', fields);
        success++;
        stdout.writeln('  ✅ $id เขียนแล้ว');
      } catch (e) {
        failed++;
        stderr.writeln('  ❌ $id ล้มเหลว: $e');
      }
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
//
// ประมาณการเดือนที่ยังไม่มีใน CSV (นับจากเดือนถัดจากแถวสุดท้ายจนถึงเดือน
// ปัจจุบันตาม DateTime.now() ตอนรัน) ด้วยหลักการ:
//   ค่าประมาณ = ค่าของ "เดือนเดียวกันเมื่อปีก่อน" (anchor ปีก่อนหน้า จับ
//               ฤดูกาลให้ตรง) x แนวโน้มการเติบโตเทียบปีต่อปี (เฉลี่ย 3 เดือน
//               ล่าสุดเทียบกับ 3 เดือนเดียวกันเมื่อปีก่อน จำกัดไว้ 0.8-1.2
//               เท่า กันเหวี่ยงเกินจริงหากข้อมูล noise สูง) x random noise
//               เล็กน้อย ±5% (seed ตาม ปี*100+เดือน เพื่อ reproducible)
// ถ้าย้อนหลังไม่ถึง 12 เดือน (ไม่มี anchor ปีก่อน) จะใช้ค่าเดือนล่าสุด
// แทน anchor (เท่ากับไม่ปรับฤดูกาล แต่ยังคูณแนวโน้มอยู่)
//
// mutate list `rows` ที่ส่งเข้ามาโดยตรง (เพิ่มแถวต่อท้าย)
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
  double total =
      (energyCost + _electricityServiceFee + ftCost) * _vatRate;
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
  double subtotal =
      cost + _waterMwaServiceFee + units * _waterMwaRawWaterFee;
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
    final doc =
        await firestore.getDocument('app_config/electricity_rates');
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
    final maskParams = fieldsToUpdate.keys
        .map((k) => 'updateMask.fieldPaths=$k')
        .join('&');
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
  final double fixedCost;
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
    required this.fixedCost,
    required this.extendToCurrent,
    required this.apply,
    required this.skipConfirm,
  });
}

_Options? _parseArgs(List<String> args) {
  String? projectId, apiKey, email, password, uid, csvPath, household, area;
  double fixedCost = 0;
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
    } else if (arg.startsWith('--fixed-cost=')) {
      fixedCost = double.parse(arg.substring('--fixed-cost='.length));
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
      household == null) {
    stderr.writeln(
        'ขาด argument ที่จำเป็น (--project-id, --api-key, --email, --csv, --household)\n');
    _printHelp();
    exitCode = 1;
    return null;
  }
  area ??= 'bangkok';
  if (area != 'bangkok' && area != 'province') {
    stderr.writeln('--area ต้องเป็น "bangkok" หรือ "province" เท่านั้น');
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
    fixedCost: fixedCost,
    extendToCurrent: extendToCurrent,
    apply: apply,
    skipConfirm: skipConfirm,
  );
}

void _printHelp() {
  stdout.writeln('''
วิธีใช้:
  dart run tool/forecast_synth/import_case_bills.dart \\
    --project-id=ID --api-key=KEY --email=EMAIL \\
    --csv=PATH --household=ID [options]

Required:
  --project-id=ID       Firebase project ID
  --api-key=KEY         Firebase Web API Key
  --email=EMAIL         อีเมลของบัญชีที่จะเพิ่มบิลให้
  --csv=PATH            path ของไฟล์ CSV เช่น tool/forecast_synth/case1_bangkok_normal.csv
  --household=ID        household_id ที่จะดึงมาใช้ เช่น case1_0000

Optional:
  --password=PASSWORD   ถ้าไม่ใส่จะถามแบบซ่อนตัวอักษรตอนรัน
  --uid=UID              เขียนบิลให้ uid อื่นที่ไม่ใช่บัญชีที่ sign-in
  --area=bangkok|province  ใช้เลือกสูตรค่าน้ำ (default: bangkok = MWA)
  --fixed-cost=NUMBER    ค่าใช้จ่ายคงที่ต่อเดือนที่จะใส่ทุกบิล (default: 0)
  --extend-to-current    ประมาณการเพิ่มให้ถึงเดือนปัจจุบัน ถ้า CSV ไม่มีข้อมูลถึงเดือนนี้
  --apply                เขียนข้อมูลจริง (ไม่ใส่ = dry-run แสดง preview เฉยๆ)
  --yes                  ข้ามการถามยืนยันตอน apply (สำหรับ non-interactive)
  --help                 แสดงข้อความนี้
''');
}