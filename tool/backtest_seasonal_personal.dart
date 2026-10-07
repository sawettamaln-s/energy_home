// backtest_seasonal_personal.dart
//
// ทดลองว่าการพยากรณ์ "บิลเดือนถัดไป" แม่นขึ้นไหม ถ้าผสมรูปแบบฤดูกาลของบ้านนั้นเอง
// เข้ากับเส้นฤดูกาลระดับประเทศ (แกนและสูตรอยู่ที่ tool/seasonal_backtest/)
// ใช้บิลรายเดือนจริงของชุดข้อมูล RECON-SL (ศรีลังกา, 4,063 บ้าน, ต.ค. 2022 – ต.ค. 2024)
//
// ไม่ให้ข้อมูลรั่ว:
// - แบ่งบ้านเป็น 5 กลุ่ม ทุกค่าที่ "เรียนรู้" (เส้นประเทศ และ λ) มาจากบ้านกลุ่มอื่นเท่านั้น
// - เส้นประเทศสร้างจากปีแรก (ต.ค. 2022 – ก.ย. 2023) ส่วนเดือนที่ทายคือ ต.ค. 2023 เป็นต้นไป
// - เส้นเฉพาะบ้านใช้แค่ 12 เดือนก่อนเดือนที่ทายของบ้านนั้น
// - เดือนที่ใช้ไฟต่ำกว่า 20 หรือเกิน 1,500 kWh ถือว่าผิดปกติ (บ้านว่าง/อ่านผิด) ตัดทิ้ง
//
// วิธีใช้:
//   dart run tool/backtest_seasonal_personal.dart \
//     --file=D:/datasets/recon-sl/data/data/consumption_data/non_smart_meter/monthly_consumption.csv

import 'dart:io';

import 'package:energy_home/utils/forecaster.dart';

import 'seasonal_backtest/seasonal_backtest.dart';

void main(List<String> args) {
  final file = args
      .where((a) => a.startsWith('--file='))
      .map((a) => a.substring('--file='.length))
      .firstOrNull;
  if (file == null) {
    stderr.writeln('วิธีใช้: dart run tool/backtest_seasonal_personal.dart --file=<monthly_consumption.csv>');
    exitCode = 1;
    return;
  }

  // household_ID,month(YYYY-MM-DD วันสิ้นเดือน),consumption
  final byHousehold = <String, MonthlySeries>{};
  for (final line in File(file).readAsLinesSync().skip(1)) {
    final p = line.split(',');
    if (p.length < 3) continue;
    final units = double.tryParse(p[2]);
    if (units == null || units < 20 || units > 1500) continue;
    final ym = p[1].split('-');
    (byHousehold[p[0]] ??= {})[monthKey(int.parse(ym[0]), int.parse(ym[1]))] = units;
  }
  final ids = byHousehold.keys.toList()..sort();
  final households = [for (final id in ids) byHousehold[id]!];

  final firstYear = monthKey(2022, 10);
  final targets = [for (var k = monthKey(2023, 10); k <= monthKey(2024, 10); k++) k];
  const folds = 5;

  final names = <String>['เท่าเดือนก่อน', 'เท่าเดือนเดียวกันปีก่อน', 'เส้นประเทศ 3 เดือน (ก่อนปรับ)'];
  for (final l in lambdaGrid) {
    names.add('ผสมเส้นบ้าน λ=${l < 1 ? l.toString() : l.toStringAsFixed(0)} (w=${(1 / (1 + l)).toStringAsFixed(2)})');
  }
  names.add('ผสมเส้นบ้าน λ เลือกด้วย CV');
  for (final w in windowGrid) {
    names.add('เส้นประเทศ ใช้ $w เดือนล่าสุด${w == EnergyForecaster.seasonalRecentMonths ? ' (แอป)' : ''}');
  }
  names.add('เส้นประเทศ จำนวนเดือนเลือกด้วย CV');
  final totals = {for (final n in names) n: Errors()};
  final chosen = <double>[];
  final chosenWindow = <int>[];

  for (var f = 0; f < folds; f++) {
    final train = [for (var i = 0; i < households.length; i++) if (i % folds != f) households[i]];
    final test = [for (var i = 0; i < households.length; i++) if (i % folds == f) households[i]];
    final national = nationalCurve(train, firstYear);

    // เลือก λ จากบ้านชุดฝึก
    var bestLambda = lambdaGrid.first;
    var bestErr = double.infinity;
    for (final l in lambdaGrid) {
      final e = score(train, targets, personalSeasonal(national, l), fullHistory).mape;
      if (e < bestErr) {
        bestErr = e;
        bestLambda = l;
      }
    }
    chosen.add(bestLambda);

    var bestWindow = windowGrid.first;
    var bestWindowErr = double.infinity;
    for (final w in windowGrid) {
      final e = score(train, targets, appSeasonal(national, window: w), fullHistory).mape;
      if (e < bestWindowErr) {
        bestWindowErr = e;
        bestWindow = w;
      }
    }
    chosenWindow.add(bestWindow);

    final methods = <String, Method>{
      names[0]: lastMonth(),
      names[1]: sameMonthLastYear(),
      names[2]: appSeasonal(national, window: 3),
      for (var i = 0; i < lambdaGrid.length; i++) names[3 + i]: personalSeasonal(national, lambdaGrid[i]),
      names[3 + lambdaGrid.length]: personalSeasonal(national, bestLambda),
      for (var i = 0; i < windowGrid.length; i++)
        names[4 + lambdaGrid.length + i]: appSeasonal(national, window: windowGrid[i]),
      names.last: appSeasonal(national, window: bestWindow),
    };
    for (final e in methods.entries) {
      totals[e.key]!.addAll(score(test, targets, e.value, fullHistory));
    }
  }

  final n = totals[names[2]]!.n;
  stdout.writeln('ชุดข้อมูล RECON-SL บิลรายเดือน · ${households.length} บ้าน · ทาย ${targets.length} เดือน '
      '(ต.ค. 2566 – ต.ค. 2567) · $n ตัวอย่างต่อวิธี · cross-validation แบ่งตามบ้าน $folds กลุ่ม\n');
  stdout.writeln('${'วิธี'.padRight(40)}  MAPE   WAPE   ความเอนเอียง');
  for (final name in names) {
    final e = totals[name]!;
    stdout.writeln('${name.padRight(40)} ${e.mape.toStringAsFixed(1).padLeft(5)}% '
        '${e.wape.toStringAsFixed(1).padLeft(5)}% ${e.bias.toStringAsFixed(1).padLeft(6)}%');
  }
  stdout.writeln('\nλ ที่ถูกเลือกจากบ้านชุดฝึกแต่ละกลุ่ม: '
      '${chosen.map((l) => l < 1 ? l.toString() : l.toStringAsFixed(0)).join(', ')}');
  stdout.writeln('จำนวนเดือนล่าสุดที่ถูกเลือกแต่ละกลุ่ม: ${chosenWindow.join(', ')}');
}
