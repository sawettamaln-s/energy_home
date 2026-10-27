// k_household_check.dart
//
// ไล่ยอดสิ้นรอบบิลที่ทายของบ้านหนึ่งหลัง (หรือทุกบ้าน) ในชุดข้อมูล RECON-SL ทีละรอบ ด้วยฟังก์ชัน
// เดียวกับแอป (EnergyForecaster.projectToCycleEnd) เทียบ k หลายค่า (ค่าเริ่มต้น
// 0 กับ 5) ไว้ใช้ตรวจกับการคำนวณที่ทำนอกแอป (เช่น notebook) ว่าได้ตัวเลขเดียวกัน
//
// การสร้างรอบใช้ cyclesFromMeter แบบเดียวกับ backtest_cycle_dataset.dart:
//   - หน่วยจริงของรอบ = เลขมิเตอร์ ณ วันตัดรอบถัดไป 00:00 − เลข ณ วันตัดรอบนี้ 00:00
//     (เลข ณ เวลาใดๆ ประมาณเชิงเส้นจากค่าก่อน-หลังที่ใกล้ที่สุด ห่างไม่เกิน 24 ชม.)
//   - จดมิเตอร์ทุกวันตอน 20:00 ไม่มีลืมจด
//   - "ทายวันที่ d" ใช้บันทึกล่าสุดก่อนเที่ยงคืนต้นวันที่ d+1 ของรอบ คือ 20:00 ของวันที่ d
//     (วันตัดรอบนับเป็นวันที่ 1) จึงผ่านไป d − 1 + 20/24 วัน
//   - บิลรอบก่อน (หน่วยต่อวัน) = หน่วยจริงรอบก่อน ÷ จำนวนวันรอบก่อน ใช้เมื่อรอบก่อนติดกัน
//     ถ้าไม่มี แอปใช้หน่วยที่ใช้แล้ว ÷ วันที่ผ่านไป (k ไม่มีผล)
//   - รอบที่ข้อมูลขาดตรงวันตัดรอบ หรือหน่วยจริงนอกช่วง 20–1,500 ถูกข้าม
//
// วิธีใช้:
//   dart run tool/k_household_check.dart --file=<recon_sl_6h.csv> --household=ID4269
//       [--billing-day=9] [--k=0,3,5] [--csv=<ไฟล์ผล.csv>] [--house-csv=<ไฟล์สรุปรายบ้าน.csv>]
// --k คั่นด้วยจุลภาค ใส่ทศนิยมได้ เช่น --k=0,2.5,5,10
// --household=all ใช้ทุกบ้านในไฟล์ด้วยเงื่อนไขเดียวกัน แสดงเฉพาะสรุป และนับว่าแต่ละ
// บ้านแม่นที่สุดที่ k ไหน (เฉลี่ยทุกจุดวัดของรอบที่มีบิลรอบก่อน)
// --house-csv บันทึกสรุปรายบ้าน 1 แถวต่อบ้าน: จำนวนรอบ, หน่วยเฉลี่ยต่อรอบ, ความแปรปรวน
// ของหน่วยระหว่างรอบ (CV %), MAPE เฉลี่ยของแต่ละ k และ k ที่แม่นที่สุด

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'cycle_backtest/cycle_backtest.dart';

Future<void> main(List<String> args) async {
  String? file;
  String? household;
  String? csvOut;
  String? houseCsvOut;
  var billingDay = 9;
  var ks = <double>[0, 5];
  for (final a in args) {
    if (a.startsWith('--file=')) {
      file = a.substring('--file='.length);
    } else if (a.startsWith('--household=')) {
      household = a.substring('--household='.length);
    } else if (a.startsWith('--billing-day=')) {
      billingDay = int.parse(a.substring('--billing-day='.length));
    } else if (a.startsWith('--k=')) {
      ks = a.substring('--k='.length).split(',').map((s) => double.parse(s.trim())).toList();
    } else if (a.startsWith('--csv=')) {
      csvOut = a.substring('--csv='.length);
    } else if (a.startsWith('--house-csv=')) {
      houseCsvOut = a.substring('--house-csv='.length);
    } else {
      stderr.writeln('ไม่รู้จัก argument: $a');
      exitCode = 1;
      return;
    }
  }
  if (file == null || household == null || ks.isEmpty) {
    stderr.writeln('วิธีใช้: dart run tool/k_household_check.dart --file=<recon_sl_6h.csv> '
        '--household=<ID|all> [--billing-day=9] [--k=0,3,5] [--csv=<ไฟล์ผล.csv>] '
        '[--house-csv=<ไฟล์สรุปรายบ้าน.csv>]');
    exitCode = 1;
    return;
  }

  final all = household == 'all';
  final seriesById = <String, List<MeterPoint>>{};
  final lines = File(file).openRead().transform(utf8.decoder).transform(const LineSplitter());
  var header = true;
  await for (final line in lines) {
    if (header) {
      header = false;
      continue;
    }
    if (!all && !line.startsWith('$household,')) continue;
    final p = line.split(',');
    if (p.length < 3) continue;
    (seriesById[p[0]] ??= []).add((at: DateTime.parse(p[1]), kwh: double.parse(p[2])));
  }
  if (seriesById.isEmpty) {
    stderr.writeln('ไม่พบบ้าน $household ในไฟล์');
    exitCode = 1;
    return;
  }

  final labels = [for (final k in ks) 'k=${_k(k)}'];
  final csv = StringBuffer('household,cycle_start,cycle_end,days,prior_per_day,actual_units,'
      'day,reading_at,used_so_far,'
      '${[for (final k in ks) 'k${_k(k)}_forecast'].join(',')},'
      '${[for (final k in ks) 'k${_k(k)}_error_pct'].join(',')}\n');
  // ความคลาดเคลื่อนสัมบูรณ์ (%) แยกตามวันที่ทายและ k: ทุกรอบ / เฉพาะรอบที่มีบิลรอบก่อน
  final errAll = {for (final d in checkpoints) d: [for (final _ in ks) <double>[]]};
  final errPrior = {for (final d in checkpoints) d: [for (final _ in ks) <double>[]]};
  // จำนวนบ้านที่ k แต่ละค่าแม่นที่สุด (เฉลี่ยทุกจุดวัดของรอบที่มีบิลรอบก่อนในบ้านนั้น)
  final bestCount = List.filled(ks.length, 0);
  final houseCsv = StringBuffer('household,cycles,mean_units,units_cv_pct,'
      '${[for (final k in ks) 'k${_k(k)}_mape'].join(',')},best_k\n');
  var cycleCount = 0;

  for (final id in seriesById.keys.toList()..sort()) {
    final series = seriesById[id]!;
    // จดทุกวันไม่มีลืม จึงไม่มีการสุ่ม (rng ไม่ถูกใช้)
    final cycles = cyclesFromMeter(series,
        billingDay: billingDay, everyDays: 1, rng: Random(1), skipChance: 0);
    if (cycles.isEmpty) continue;
    cycleCount += cycles.length;
    final houseSum = List.filled(ks.length, 0.0);
    var houseN = 0;

    if (!all) {
      stdout.writeln('บ้าน $id · วันตัดรอบวันที่ $billingDay · ${cycles.length} รอบ');
      stdout.writeln('ข้อมูล ${_d(series.first.at)} ถึง ${_d(series.last.at)}\n');
    }
    for (final c in cycles) {
      final end = c.end.subtract(const Duration(days: 1));
      if (!all) {
        stdout.writeln('รอบ ${_d(c.start)} – ${_d(end)} (${c.days} วัน) · ใช้จริง '
            '${c.actualUnits.toStringAsFixed(2)} หน่วย · บิลรอบก่อน '
            '${c.priorPerDay == null ? 'ไม่มี' : '${c.priorPerDay!.toStringAsFixed(3)} หน่วย/วัน'}');
        stdout.writeln('  วันที่  ใช้แล้ว${[for (final l in labels) '${l.padLeft(9)} ทาย (คลาด)'].join()}');
      }
      for (final d in checkpoints) {
        final r = c.latestAtDay(d);
        if (r == null) continue;
        final forecasts = [for (final k in ks) projectAt(c, d, k)];
        if (forecasts.any((f) => f == null)) continue;
        final errors = [for (final f in forecasts) (f! - c.actualUnits) / c.actualUnits * 100];
        for (var i = 0; i < ks.length; i++) {
          errAll[d]![i].add(errors[i].abs());
          if (c.priorPerDay != null) {
            errPrior[d]![i].add(errors[i].abs());
            houseSum[i] += errors[i].abs();
          }
        }
        if (c.priorPerDay != null) houseN++;
        if (!all) {
          stdout.writeln('  ${d.toString().padLeft(4)}  ${r.usedFromStart.toStringAsFixed(2).padLeft(7)}'
              '${[for (var i = 0; i < ks.length; i++) '  ${forecasts[i]!.toStringAsFixed(2).padLeft(8)} (${_pct(errors[i])})'].join()}');
        }
        if (csvOut != null) {
          csv.writeln('$id,${_d(c.start)},${_d(end)},${c.days},${c.priorPerDay?.toStringAsFixed(6) ?? ''},'
              '${c.actualUnits.toStringAsFixed(4)},$d,${r.at.toIso8601String()},'
              '${r.usedFromStart.toStringAsFixed(4)},${forecasts.join(',')},'
              '${errors.map((e) => e.toStringAsFixed(4)).join(',')}');
        }
      }
      if (!all) stdout.writeln();
    }
    if (houseN > 0) {
      var best = 0;
      for (var i = 1; i < ks.length; i++) {
        if (houseSum[i] < houseSum[best]) best = i;
      }
      bestCount[best]++;
      final units = [for (final c in cycles) c.actualUnits];
      final mean = _avg(units);
      final sd = sqrt(_avg([for (final u in units) (u - mean) * (u - mean)]));
      houseCsv.writeln('$id,${cycles.length},${mean.toStringAsFixed(2)},'
          '${(sd / mean * 100).toStringAsFixed(2)},'
          '${[for (final t in houseSum) (t / houseN).toStringAsFixed(4)].join(',')},${_k(ks[best])}');
    }
  }

  if (all) {
    stdout.writeln('ทุกบ้าน · วันตัดรอบวันที่ $billingDay · จดทุกวัน 20:00 · '
        '${seriesById.length} บ้านในไฟล์ · $cycleCount รอบ\n');
  }
  _summary('ทุกรอบ', errAll, labels);
  _summary('เฉพาะรอบที่มีบิลรอบก่อน (k มีผล)', errPrior, labels);
  if (all) {
    final houses = bestCount.reduce((a, b) => a + b);
    stdout.writeln('===== จำนวนบ้านที่ k แต่ละค่าแม่นที่สุด ($houses บ้าน) =====');
    for (var i = 0; i < ks.length; i++) {
      stdout.writeln('  ${labels[i].padLeft(6)}  ${bestCount[i].toString().padLeft(5)} บ้าน'
          '  (${(bestCount[i] / houses * 100).toStringAsFixed(1)}%)');
    }
  }
  if (houseCsvOut != null) {
    File(houseCsvOut).writeAsStringSync(houseCsv.toString());
    stdout.writeln('\nบันทึกสรุปรายบ้านที่ $houseCsvOut');
  }
  if (csvOut != null) {
    File(csvOut).writeAsStringSync(csv.toString());
    stdout.writeln('\nบันทึกผลที่ $csvOut');
  }
}

void _summary(String title, Map<int, List<List<double>>> err, List<String> labels) {
  stdout.writeln('===== คลาดเคลื่อนเฉลี่ย (MAPE %) $title =====');
  stdout.writeln('  วันที่${[for (final l in labels) l.padLeft(8)].join()}    รอบ');
  final total = List.filled(labels.length, 0.0);
  var count = 0;
  for (final d in checkpoints) {
    final n = err[d]![0].length;
    if (n == 0) continue;
    for (var i = 0; i < labels.length; i++) {
      total[i] += _avg(err[d]![i]);
    }
    count++;
    stdout.writeln('  ${d.toString().padLeft(4)}'
        '${[for (final e in err[d]!) _avg(e).toStringAsFixed(2).padLeft(8)].join()}'
        '  ${n.toString().padLeft(5)}');
  }
  if (count > 0) {
    stdout.writeln('  เฉลี่ย${[for (final t in total) (t / count).toStringAsFixed(2).padLeft(8)].join()}');
  }
}

String _k(double k) => k == k.roundToDouble() ? k.toInt().toString() : k.toString();

String _d(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

String _pct(double e) => '${e >= 0 ? '+' : ''}${e.toStringAsFixed(1)}%'.padLeft(7);

double _avg(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
