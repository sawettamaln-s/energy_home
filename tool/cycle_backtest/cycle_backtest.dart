// แกนคำนวณของสคริปต์วัดความแม่นยำ "ยอดสิ้นรอบบิล" (tool/backtest_cycle_projection.dart)
// เป็น Dart ล้วน ไม่แตะ Firebase จึงเทสได้ (test/cycle_backtest_test.dart)
//
// หลักการ (backtest ย้อนหลัง):
//   1. หน่วยจริงของรอบที่ปิดแล้ว = เลขต้นรอบของรอบถัดไป − เลขต้นรอบของรอบนั้น
//      (มาจากใบแจ้งหนี้ ไม่ใช่ยอดที่ระบบประมาณ)
//   2. แกล้งทำเป็นอยู่ ณ วันที่ d ของรอบ (3, 5, 7, 10, 15, 20, 25) ใช้เฉพาะ
//      บันทึกมิเตอร์ที่มีถึงวันนั้น แล้วคาดการณ์ยอดสิ้นรอบด้วยฟังก์ชันเดียวกับแอป
//      (EnergyForecaster.projectToCycleEnd)
//   3. เทียบกับหน่วยจริง → MAPE / MAE / ความเอนเอียง (bias)
//   4. ลองน้ำหนักบิลรอบก่อน (k วัน) หลายค่า และเลือก k ด้วย leave-one-cycle-out
//      cross-validation: ทุกรอบถูกทำนายด้วย k ที่เลือกจากรอบอื่นเท่านั้น
//      ความแม่นยำที่รายงานจึงไม่ได้มาจากการเลือก k ให้เข้ากับข้อมูลชุดทดสอบเอง

import 'package:energy_home/utils/forecaster.dart';

// บันทึกมิเตอร์ 1 ครั้ง: วันเวลา + หน่วยสะสมตั้งแต่ต้นรอบ (usedFromStart)
typedef Reading = ({DateTime at, double usedFromStart});

class BacktestCycle {
  final DateTime start;
  final DateTime end;
  final double actualUnits; // หน่วยจริงทั้งรอบ (จากเลขต้นรอบถัดไป)
  final double? priorPerDay; // หน่วยต่อวันของรอบก่อนหน้า (null = ไม่มี)
  final List<Reading> readings; // บันทึกในรอบนี้ เรียงเก่า -> ใหม่

  BacktestCycle({
    required this.start,
    required this.end,
    required this.actualUnits,
    required this.priorPerDay,
    required List<Reading> readings,
  }) : readings = [...readings]..sort((a, b) => a.at.compareTo(b.at));

  int get days => end.difference(start).inDays;

  String get label => '${start.year}-${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';

  // บันทึกล่าสุด ณ วันที่ [day] ของรอบ (นับจากต้นรอบ) — null = ยังไม่มี
  Reading? latestAtDay(int day) {
    final cutoff = start.add(Duration(days: day));
    Reading? latest;
    for (final r in readings) {
      if (r.at.isAfter(cutoff)) break;
      latest = r;
    }
    return latest;
  }
}

// เลขต้นรอบ 1 รอบ: ปี/เดือนที่รอบเริ่ม + เลขมิเตอร์ (TOU = On + Off รวมกัน)
typedef StartReading = ({int year, int month, double value});

// สร้างรอบที่ปิดแล้วจากเลขต้นรอบที่ต่อเนื่องกัน + บันทึกมิเตอร์รายวัน
// รอบที่ไม่มีเลขต้นรอบถัดไป, หน่วยจริง ≤ 0 (เช่น เปลี่ยนมิเตอร์) หรือไม่มีบันทึก
// ในรอบเลย จะไม่ถูกนำมาวัด
List<BacktestCycle> buildCycles({
  required List<StartReading> starts,
  required List<Reading> readings,
  required int billingDay,
}) {
  final byKey = {for (final s in starts) s.year * 12 + s.month: s};
  final keys = byKey.keys.toList()..sort();
  final cycles = <BacktestCycle>[];
  double? prevPerDay;
  int? prevKey;
  for (final key in keys) {
    final s = byKey[key]!;
    final next = byKey[key + 1];
    final start = EnergyForecaster.safeBillingDate(s.year, s.month, billingDay);
    final nextMonth = DateTime(s.year, s.month + 1, 1);
    final end = EnergyForecaster.safeBillingDate(nextMonth.year, nextMonth.month, billingDay);
    final actual = next == null ? 0.0 : next.value - s.value;
    // หน่วยต่อวันของรอบก่อนใช้ได้เฉพาะเมื่อรอบก่อนติดกันจริง
    final prior = prevKey == key - 1 ? prevPerDay : null;
    if (next != null && actual > 0) {
      final inCycle = [
        for (final r in readings)
          if (!r.at.isBefore(start) && r.at.isBefore(end)) r,
      ];
      if (inCycle.isNotEmpty) {
        cycles.add(BacktestCycle(
          start: start,
          end: end,
          actualUnits: actual,
          priorPerDay: prior,
          readings: inCycle,
        ));
      }
      prevPerDay = actual / end.difference(start).inDays;
    } else {
      prevPerDay = null;
    }
    prevKey = key;
  }
  return cycles;
}

// วันที่ในรอบที่ใช้เป็นจุดวัด
const List<int> checkpoints = [3, 5, 7, 10, 15, 20, 25];

// ค่า k (น้ำหนักบิลรอบก่อน หน่วย: วัน) ที่ลองใน grid — 0 = ใช้ข้อมูลรอบนี้อย่างเดียว
const List<double> weightGrid = [0, 1, 2, 3, 5, 7, 10, 14, 21];

// คาดการณ์ยอดสิ้นรอบ ณ วันที่ [day] ด้วยน้ำหนัก [k] — null = วันนั้นยังคาดการณ์ไม่ได้
double? projectAt(BacktestCycle c, int day, double k) {
  if (day >= c.days) return null;
  final r = c.latestAtDay(day);
  if (r == null) return null;
  return EnergyForecaster.projectToCycleEnd(
    currentTotal: r.usedFromStart,
    cycleStart: c.start,
    cycleEnd: c.end,
    lastRecordedAt: r.at,
    priorPerDay: c.priorPerDay,
    priorWeight: k,
  );
}

class ErrorStats {
  final List<double> _pct = []; // % error แบบมีเครื่องหมาย (ทำนาย − จริง) ÷ จริง
  final List<double> _abs = []; // หน่วย

  void add(double predicted, double actual) {
    _pct.add((predicted - actual) / actual * 100);
    _abs.add((predicted - actual).abs());
  }

  int get n => _pct.length;
  double get mape => n == 0 ? double.nan : _pct.map((e) => e.abs()).reduce((a, b) => a + b) / n;
  double get mae => n == 0 ? double.nan : _abs.reduce((a, b) => a + b) / n;
  double get bias => n == 0 ? double.nan : _pct.reduce((a, b) => a + b) / n;
}

// ความคลาดเคลื่อนของน้ำหนัก [k] ต่อจุดวัด จากรอบใน [cycles]
Map<int, ErrorStats> evaluate(List<BacktestCycle> cycles, double k) {
  final result = {for (final d in checkpoints) d: ErrorStats()};
  for (final c in cycles) {
    for (final d in checkpoints) {
      final p = projectAt(c, d, k);
      if (p != null) result[d]!.add(p, c.actualUnits);
    }
  }
  return result;
}

// baseline: ไม่ใช้ข้อมูลรอบนี้เลย ทายว่าเท่ารอบก่อน (หน่วยต่อวันรอบก่อน × จำนวนวัน)
Map<int, ErrorStats> evaluatePreviousCycle(List<BacktestCycle> cycles) {
  final result = {for (final d in checkpoints) d: ErrorStats()};
  for (final c in cycles) {
    final prior = c.priorPerDay;
    if (prior == null) continue;
    for (final d in checkpoints) {
      if (projectAt(c, d, 0) == null) continue; // วัดเฉพาะจุดเดียวกับวิธีอื่น
      result[d]!.add(prior * c.days, c.actualUnits);
    }
  }
  return result;
}

// MAPE เฉลี่ยทุกจุดวัด (ถ่วงตามจำนวนตัวอย่าง) — ใช้เลือก k
double overallMape(Map<int, ErrorStats> stats) {
  var sum = 0.0;
  var n = 0;
  for (final s in stats.values) {
    if (s.n == 0) continue;
    sum += s.mape * s.n;
    n += s.n;
  }
  return n == 0 ? double.nan : sum / n;
}

double bestWeight(List<BacktestCycle> cycles) {
  var best = weightGrid.first;
  var bestErr = double.infinity;
  for (final k in weightGrid) {
    final err = overallMape(evaluate(cycles, k));
    if (!err.isNaN && err < bestErr) {
      bestErr = err;
      best = k;
    }
  }
  return best;
}

// leave-one-cycle-out: เลือก k จากรอบอื่น แล้วทำนายรอบที่กันไว้ ผลคือ
// ความแม่นยำที่คาดได้กับรอบใหม่ที่ไม่เคยเห็น และ k ที่ถูกเลือกในแต่ละรอบ
({Map<int, ErrorStats> stats, List<double> chosen}) crossValidate(List<BacktestCycle> cycles) {
  final result = {for (final d in checkpoints) d: ErrorStats()};
  final chosen = <double>[];
  for (var i = 0; i < cycles.length; i++) {
    final train = [...cycles]..removeAt(i);
    final k = train.isEmpty ? EnergyForecaster.priorWeightDays : bestWeight(train);
    chosen.add(k);
    final test = cycles[i];
    for (final d in checkpoints) {
      final p = projectAt(test, d, k);
      if (p != null) result[d]!.add(p, test.actualUnits);
    }
  }
  return (stats: result, chosen: chosen);
}

// รายงานผลเป็นข้อความตาราง
String report(String title, List<BacktestCycle> cycles) {
  final b = StringBuffer();
  b.writeln('===== $title =====');
  if (cycles.isEmpty) {
    b.writeln('ไม่มีรอบที่ปิดแล้วพร้อมบันทึกมิเตอร์ให้วัด\n');
    return b.toString();
  }
  final withPrior = cycles.where((c) => c.priorPerDay != null).length;
  b.writeln('รอบที่วัดได้ ${cycles.length} รอบ (มีบิลรอบก่อนให้ถ่วง $withPrior รอบ)');
  b.writeln('ค่าที่แสดง = MAPE (%) ของหน่วยทั้งรอบ ณ วันที่ของรอบ  [n = จำนวนตัวอย่าง]\n');

  String row(String name, Map<int, ErrorStats> s) {
    final cells = [for (final d in checkpoints) s[d]!.n == 0 ? '   -  ' : s[d]!.mape.toStringAsFixed(1).padLeft(6)];
    final all = overallMape(s);
    return '${name.padRight(30)}${cells.join(' ')}   ${all.isNaN ? '  -' : all.toStringAsFixed(1).padLeft(5)}';
  }

  b.writeln('${'วิธี'.padRight(30)}${[for (final d in checkpoints) 'วัน${d.toString().padLeft(2)}'.padLeft(6)].join(' ')}   เฉลี่ย');
  b.writeln(row('ทายเท่ารอบก่อน (baseline)', evaluatePreviousCycle(cycles)));
  for (final k in weightGrid) {
    final name = k == 0
        ? 'อัตราต่อวันอย่างเดียว (k=0)'
        : 'ถ่วงบิลรอบก่อน k=${k.toStringAsFixed(0)}${k == EnergyForecaster.priorWeightDays ? ' (แอป)' : ''}';
    b.writeln(row(name, evaluate(cycles, k)));
  }
  final n = evaluate(cycles, EnergyForecaster.priorWeightDays);
  b.writeln('${'  n (ตัวอย่างต่อจุดวัด)'.padRight(30)}${[for (final d in checkpoints) n[d]!.n.toString().padLeft(6)].join(' ')}');

  final appStats = evaluate(cycles, EnergyForecaster.priorWeightDays);
  b.writeln('\nความเอนเอียงของแอป (k=${EnergyForecaster.priorWeightDays.toStringAsFixed(0)}): '
      '${overallBias(appStats).toStringAsFixed(1)}% (บวก = ทายสูงกว่าจริง)');
  b.writeln('MAE ของแอป: ${overallMae(appStats).toStringAsFixed(1)} หน่วย');

  final best = bestWeight(cycles);
  b.writeln('\nk ที่แม่นที่สุดกับข้อมูลชุดนี้ = ${best.toStringAsFixed(0)} '
      '(MAPE เฉลี่ย ${overallMape(evaluate(cycles, best)).toStringAsFixed(1)}%)');
  if (cycles.length >= 3) {
    final cv = crossValidate(cycles);
    b.writeln('leave-one-cycle-out (เลือก k จากรอบอื่น ทดสอบกับรอบที่กันไว้): '
        'MAPE ${overallMape(cv.stats).toStringAsFixed(1)}%, '
        'k ที่ถูกเลือก ${cv.chosen.map((k) => k.toStringAsFixed(0)).join(', ')}');
  } else {
    b.writeln('ข้อมูลน้อยกว่า 3 รอบ ยังทำ cross-validation ไม่ได้');
  }
  b.writeln();
  return b.toString();
}

double overallBias(Map<int, ErrorStats> stats) => _weighted(stats, (s) => s.bias);
double overallMae(Map<int, ErrorStats> stats) => _weighted(stats, (s) => s.mae);

double _weighted(Map<int, ErrorStats> stats, double Function(ErrorStats) f) {
  var sum = 0.0;
  var n = 0;
  for (final s in stats.values) {
    if (s.n == 0) continue;
    sum += f(s) * s.n;
    n += s.n;
  }
  return n == 0 ? double.nan : sum / n;
}
