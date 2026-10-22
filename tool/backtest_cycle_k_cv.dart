// backtest_cycle_k_cv.dart
//
// หลักฐานว่า k (EnergyForecaster.priorWeightDays) = 5 เป็นค่าที่เหมาะสมหรือไม่
// บนชุดข้อมูล RECON-SL โดยใช้ cross-validation แบ่งตามบ้าน
//
// ต่างจาก report() เดิมที่รายงานแค่ "k ที่ถูกเลือกในแต่ละ fold" สคริปต์นี้เพิ่ม
//   1. ตาราง MAPE ของ "ทุก k" บนบ้านที่กันไว้ (held-out) ของแต่ละ fold
//      เพื่อดูว่า k=5 ชนะทุก fold หรือไม่ และกราฟแบนแค่ไหนรอบ k=5
//   2. bootstrap แบบสุ่มบ้านซ้ำ (resample households) เพื่อหาช่วงความเชื่อมั่น 95%
//      ของ MAPE(k) - MAPE(5) และความน่าจะเป็นที่แต่ละ k เป็นค่าที่ดีที่สุด
//   3. ผล CV แบบเดิม (เลือก k จากกลุ่มอื่น) เพื่อเทียบ
//
//   4. (ไม่บังคับ) stress test ฤดูกาลไทย: คูณหน่วยที่ใช้ในแต่ละช่วงด้วยแฟกเตอร์รายเดือน
//      ของไทยจาก seasonal_curves.json แล้วหาค่า k ใหม่ ข้อมูลศรีลังกามีฤดูกาลของตัวเอง
//      อยู่แล้ว ผลนี้จึงบอกความไวของ k ต่อฤดูกาลที่แรงแบบไทย ไม่ใช่การจำลองบ้านไทยจริง
//
// วิธีสร้างรอบบิลเหมือน tool/backtest_cycle_dataset.dart แต่แต่ละบ้านมีตัวสุ่มของตัวเอง
// (seed + ลำดับบ้านตาม ID) และ fold ของบ้านกำหนดจากลำดับเดียวกัน รอบที่ถูกกรองทิ้งของ
// บ้านหนึ่งจึงไม่ทำให้วันตัดรอบ ตารางจดมิเตอร์ หรือ fold ของบ้านอื่นเปลี่ยน การรันปกติกับ
// --thai-seasonal ที่ seed เดียวกันจึงต่างกันแค่ฤดูกาล ผลจึงไม่ตรงกับสคริปต์เดิมทุกตัวเลข
//
// วิธีใช้:
//   dart run tool/backtest_cycle_k_cv.dart --file=<recon_sl_6h.csv> [--seed=1] [--rounds=1000]
//       [--thai-seasonal=tool/seasonal_curves/seasonal_curves.json] [--curve=bangkok_normal]
//       [--csv=<ไฟล์ผลสำหรับทำกราฟ.csv>]
//   --curve เลือกเส้นไฟฟ้าใน seasonal_curves.json (bangkok_normal, upcountry_normal, ...)
//   เก็บผลไว้เป็นหลักฐาน:  ... > docs/k_cv_detail_seed1.txt

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'cycle_backtest/cycle_backtest.dart';

// กริดละเอียดกว่าของเดิม (เพิ่ม 4, 6, 8) เพื่อตอบคำถาม "ทำไมไม่ใช่ 4 หรือ 6"
const List<double> kGrid = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 14, 21];
const int folds = 5;

class _Acc {
  double sum = 0; // ผลรวม |%error|
  int n = 0; // จำนวนตัวอย่าง (บ้าน x รอบ x จุดวัด)
}

double _percentile(List<double> sorted, double p) =>
    sorted[((sorted.length - 1) * p).round()];

String _f(double v, [int d = 2]) => v.toStringAsFixed(d);

// คูณหน่วยที่เพิ่มขึ้นในแต่ละช่วงด้วยแฟกเตอร์ของเดือนที่ช่วงนั้นสิ้นสุด แล้วสะสมเป็น
// เลขมิเตอร์ชุดใหม่ [factors] = 12 ค่า (มกราคม-ธันวาคม) prepare_recon_sl.py ตัดค่าที่
// ถอยหลังออกแล้ว หน่วยที่เพิ่มขึ้นจึงไม่ติดลบ
List<MeterPoint> applyThaiSeasonality(List<MeterPoint> s, List<double> factors) {
  if (s.length < 2) return s;
  final out = <MeterPoint>[s.first];
  var cum = s.first.kwh;
  for (var i = 1; i < s.length; i++) {
    cum += (s[i].kwh - s[i - 1].kwh) * factors[s[i].at.month - 1];
    out.add((at: s[i].at, kwh: cum));
  }
  return out;
}

Future<void> main(List<String> args) async {
  String? file;
  var seed = 1;
  var rounds = 1000;
  String? thaiPath;
  var curve = 'bangkok_normal';
  String? csvPath;
  for (final a in args) {
    if (a.startsWith('--file=')) {
      file = a.substring('--file='.length);
    } else if (a.startsWith('--seed=')) {
      seed = int.parse(a.substring('--seed='.length));
    } else if (a.startsWith('--rounds=')) {
      rounds = int.parse(a.substring('--rounds='.length));
    } else if (a.startsWith('--thai-seasonal=')) {
      thaiPath = a.substring('--thai-seasonal='.length);
    } else if (a.startsWith('--curve=')) {
      curve = a.substring('--curve='.length);
    } else if (a.startsWith('--csv=')) {
      csvPath = a.substring('--csv='.length);
    } else {
      stderr.writeln('ไม่รู้จัก argument: $a');
      exitCode = 1;
      return;
    }
  }
  if (file == null) {
    stderr.writeln('วิธีใช้: dart run tool/backtest_cycle_k_cv.dart --file=<recon_sl_6h.csv> [--seed=1] [--rounds=1000]');
    exitCode = 1;
    return;
  }

  // ---------- โหลดข้อมูลและสร้างบ้าน (เหมือน backtest_cycle_dataset.dart) ----------
  final series = <String, List<MeterPoint>>{};
  final lines = File(file).openRead().transform(utf8.decoder).transform(const LineSplitter());
  var header = true;
  await for (final line in lines) {
    if (header) {
      header = false;
      continue;
    }
    final p = line.split(',');
    if (p.length < 3) continue;
    (series[p[0]] ??= []).add((at: DateTime.parse(p[1]), kwh: double.parse(p[2])));
  }

  String seasonNote = 'ไม่ปรับฤดูกาล';
  if (thaiPath != null) {
    final curves = jsonDecode(File(thaiPath).readAsStringSync())['curves']['elec'] as Map<String, dynamic>;
    final raw = curves[curve];
    if (raw is! List || raw.length != 12) {
      stderr.writeln('ไม่พบเส้นฤดูกาล "$curve" (มี: ${curves.keys.join(', ')})');
      exitCode = 1;
      return;
    }
    final factors = [for (final v in raw) (v as num).toDouble()];
    for (final id in series.keys.toList()) {
      series[id] = applyThaiSeasonality(series[id]!, factors);
    }
    seasonNote = 'ปรับฤดูกาลไทย $curve (แฟกเตอร์ ${_f(factors.reduce(min))}-${_f(factors.reduce(max))})';
  }

  // ทุกบ้านอยู่ในรายการตามลำดับ ID แม้ไม่มีรอบที่ใช้ได้ (รายการว่างไม่มีผลต่อสถิติ)
  // fold ของบ้านลำดับ i คือ i % folds ทั้งในสคริปต์นี้และ crossValidateByHousehold
  final households = <List<BacktestCycle>>[];
  final ids = series.keys.toList()..sort();
  for (var i = 0; i < ids.length; i++) {
    final rng = Random(seed * 100003 + i);
    final everyDays = 1 + rng.nextInt(3);
    households.add(cyclesFromMeter(
      series[ids[i]]!,
      billingDay: 1 + rng.nextInt(28),
      everyDays: everyDays,
      rng: rng,
    ));
  }
  final usable = households.where((h) => h.isNotEmpty).length;
  if (usable < folds * 2) {
    stderr.writeln('บ้านน้อยเกินไป ($usable) สำหรับ $folds-fold CV');
    exitCode = 1;
    return;
  }

  // ---------- สถิติรายบ้าน x รายค่า k ----------
  // MAPE รวมของโปรเจกต์ = ถ่วงตามจำนวนตัวอย่างต่อจุดวัด = ผลรวม|%error| ÷ จำนวนตัวอย่าง
  final stat = <List<_Acc>>[];
  for (final h in households) {
    final row = [for (final _ in kGrid) _Acc()];
    for (var ki = 0; ki < kGrid.length; ki++) {
      for (final c in h) {
        for (final d in checkpoints) {
          final p = projectAt(c, d, kGrid[ki]);
          if (p == null) continue;
          row[ki].sum += ((p - c.actualUnits) / c.actualUnits * 100).abs();
          row[ki].n++;
        }
      }
    }
    stat.add(row);
  }

  double mapeOf(Iterable<int> idx, int ki) {
    var s = 0.0;
    var n = 0;
    for (final i in idx) {
      s += stat[i][ki].sum;
      n += stat[i][ki].n;
    }
    return n == 0 ? double.nan : s / n;
  }

  final k5 = kGrid.indexOf(5);
  final all = List<int>.generate(households.length, (i) => i);
  final totalRounds = households.fold<int>(0, (a, h) => a + h.length);

  final out = StringBuffer();
  out.writeln('ชุดข้อมูล RECON-SL · seed $seed · $seasonNote');
  out.writeln('บ้านที่ใช้ได้ $usable จาก ${households.length} บ้าน · รอบที่ปิดแล้ว $totalRounds รอบ');
  out.writeln('MAPE (%) บนบ้านที่กันไว้ในแต่ละ fold (ยิ่งต่ำยิ่งดี, * = ต่ำสุดของแถว)\n');

  // ---------- 1) ตาราง fold x k ----------
  out.write('fold  ');
  for (final k in kGrid) {
    out.write('k=${k.toStringAsFixed(0)}'.padLeft(8));
  }
  out.writeln('   ดีที่สุด');
  final wins = List<int>.filled(kGrid.length, 0);
  for (var f = 0; f < folds; f++) {
    final test = all.where((i) => i % folds == f).toList();
    final m = [for (var ki = 0; ki < kGrid.length; ki++) mapeOf(test, ki)];
    var best = 0;
    for (var ki = 1; ki < m.length; ki++) {
      if (m[ki] < m[best]) best = ki;
    }
    wins[best]++;
    out.write('${f + 1}'.padRight(6));
    for (var ki = 0; ki < m.length; ki++) {
      out.write('${_f(m[ki])}${ki == best ? '*' : ' '}'.padLeft(8));
    }
    out.writeln('   k=${kGrid[best].toStringAsFixed(0)}');
  }
  final overall = [for (var ki = 0; ki < kGrid.length; ki++) mapeOf(all, ki)];
  out.write('รวม   ');
  var overallBest = 0;
  for (var ki = 1; ki < overall.length; ki++) {
    if (overall[ki] < overall[overallBest]) overallBest = ki;
  }
  for (var ki = 0; ki < overall.length; ki++) {
    out.write('${_f(overall[ki])}${ki == overallBest ? '*' : ' '}'.padLeft(8));
  }
  out.writeln('   k=${kGrid[overallBest].toStringAsFixed(0)}');
  out.writeln('\nจำนวน fold ที่แต่ละ k ชนะ: '
      '${[for (var ki = 0; ki < kGrid.length; ki++) if (wins[ki] > 0) 'k=${kGrid[ki].toStringAsFixed(0)}: ${wins[ki]}/$folds'].join(' · ')}');

  // ---------- 2) bootstrap สุ่มบ้านซ้ำ ----------
  final brng = Random(seed + 1000);
  final bestCount = List<int>.filled(kGrid.length, 0);
  final diffs = [for (final _ in kGrid) <double>[]]; // MAPE(k) - MAPE(5)
  for (var b = 0; b < rounds; b++) {
    final sum = List<double>.filled(kGrid.length, 0);
    final cnt = List<int>.filled(kGrid.length, 0);
    for (var i = 0; i < households.length; i++) {
      final h = brng.nextInt(households.length);
      for (var ki = 0; ki < kGrid.length; ki++) {
        sum[ki] += stat[h][ki].sum;
        cnt[ki] += stat[h][ki].n;
      }
    }
    if (cnt[k5] == 0) continue;
    final m = [for (var ki = 0; ki < kGrid.length; ki++) sum[ki] / cnt[ki]];
    var best = 0;
    for (var ki = 1; ki < m.length; ki++) {
      if (m[ki] < m[best]) best = ki;
    }
    bestCount[best]++;
    for (var ki = 0; ki < kGrid.length; ki++) {
      diffs[ki].add(m[ki] - m[k5]);
    }
  }
  out.writeln('\n===== bootstrap สุ่มบ้านซ้ำ $rounds รอบ (เทียบกับ k=5) =====');
  out.writeln('${'k'.padRight(5)}${'P(ดีที่สุด)'.padLeft(12)}${'MAPE(k)-MAPE(5)'.padLeft(18)}${'ช่วง 95%'.padLeft(24)}');
  for (var ki = 0; ki < kGrid.length; ki++) {
    final d = [...diffs[ki]]..sort();
    final mean = d.reduce((a, b) => a + b) / d.length;
    final lo = _percentile(d, 0.025);
    final hi = _percentile(d, 0.975);
    out.writeln('${'k=${kGrid[ki].toStringAsFixed(0)}'.padRight(5)}'
        '${(bestCount[ki] / diffs[k5].length * 100).toStringAsFixed(1).padLeft(11)}%'
        '${_f(mean, 3).padLeft(18)}'
        '${'[${_f(lo, 3)}, ${_f(hi, 3)}]'.padLeft(24)}');
  }
  out.writeln('(ส่วนต่างเป็นบวก = k นั้นแย่กว่า k=5 · ถ้าช่วง 95% คร่อมศูนย์ = แยกจาก k=5 ไม่ออกทางสถิติ)');

  if (csvPath != null) {
    final csv = StringBuffer('k,mape,diff_mean,diff_lo,diff_hi,p_best\n');
    final used = diffs[k5].length;
    for (var ki = 0; ki < kGrid.length; ki++) {
      final d = [...diffs[ki]]..sort();
      final mean = d.reduce((a, b) => a + b) / d.length;
      csv.writeln('${kGrid[ki]},${overall[ki]},$mean,'
          '${_percentile(d, 0.025)},${_percentile(d, 0.975)},${bestCount[ki] / used}');
    }
    File(csvPath).parent.createSync(recursive: true);
    File(csvPath).writeAsStringSync(csv.toString());
  }

  // ---------- 3) CV แบบเดิม (เลือก k จากกลุ่มอื่น) ----------
  final cv = crossValidateByHousehold(households, folds: folds);
  out.writeln('\n===== CV แบบเดิมของโปรเจกต์ (เลือก k จากกลุ่มอื่น แล้วทดสอบกลุ่มที่กันไว้) =====');
  out.writeln('MAPE ${_f(overallMape(cv.stats), 2)}% · k ที่ถูกเลือกแต่ละ fold: '
      '${cv.chosen.map((k) => k.toStringAsFixed(0)).join(', ')}');

  stdout.write(out);
}
