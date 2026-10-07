// backtest_cycle_dataset.dart
//
// วัดความแม่นยำของ "ยอดสิ้นรอบบิล" กับข้อมูลมิเตอร์อัจฉริยะจริงของหลายครัวเรือน
// (ชุดข้อมูล RECON-SL ศรีลังกา เขตร้อนชื้นใกล้ไทย) ใช้ฟังก์ชันคาดการณ์เดียวกับแอป
// และวิธีวัดผลเดียวกับ tool/backtest_cycle_projection.dart (แกนอยู่ที่ cycle_backtest/)
//
// ข้อมูลจริง: เลขมิเตอร์สะสมทุก ~6 ชั่วโมง → หน่วยจริงของแต่ละรอบ และเลขที่ผู้ใช้
// จะอ่านได้ ณ เวลาใดๆ ส่วนที่จำลอง: วันตัดรอบของแต่ละบ้าน (สุ่ม 1-28) และตาราง
// การจดมิเตอร์ (ตอน 20:00 ทุก 1, 2 หรือ 3 วัน ลืมจด 20% ของครั้ง) แบบผู้ใช้แอป
// สุ่มด้วย seed คงที่ รันซ้ำได้ผลเดิม
//
// ขั้นตอน:
//   1. ดาวน์โหลด RECON-SL (IEEE DataPort, DOI 10.21227/n1dk-q860, CC BY 4.0)
//   2. python tool/cycle_backtest/prepare_recon_sl.py --data <โฟลเดอร์ data> --out <ไฟล์.csv>
//   3. dart run tool/backtest_cycle_dataset.dart --file=<ไฟล์.csv> [--seed=1]

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'cycle_backtest/cycle_backtest.dart';

Future<void> main(List<String> args) async {
  String? file;
  var seed = 1;
  for (final a in args) {
    if (a.startsWith('--file=')) {
      file = a.substring('--file='.length);
    } else if (a.startsWith('--seed=')) {
      seed = int.parse(a.substring('--seed='.length));
    } else {
      stderr.writeln('ไม่รู้จัก argument: $a');
      exitCode = 1;
      return;
    }
  }
  if (file == null) {
    stderr.writeln('วิธีใช้: dart run tool/backtest_cycle_dataset.dart --file=<recon_sl_6h.csv> [--seed=1]');
    exitCode = 1;
    return;
  }

  // household,timestamp,kwh เรียงตามบ้านแล้วตามเวลา (จาก prepare_recon_sl.py)
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

  final rng = Random(seed);
  final households = <List<BacktestCycle>>[];
  final byFrequency = <int, List<BacktestCycle>>{1: [], 2: [], 3: []};
  for (final id in series.keys.toList()..sort()) {
    final everyDays = 1 + rng.nextInt(3);
    final cycles = cyclesFromMeter(
      series[id]!,
      billingDay: 1 + rng.nextInt(28),
      everyDays: everyDays,
      rng: rng,
    );
    if (cycles.isEmpty) continue;
    households.add(cycles);
    byFrequency[everyDays]!.addAll(cycles);
  }
  final all = [for (final h in households) ...h];
  final units = all.map((c) => c.actualUnits).toList()..sort();

  stdout.writeln('ชุดข้อมูล RECON-SL (ศรีลังกา) · seed $seed');
  stdout.writeln('บ้านที่ใช้ได้ ${households.length} บ้าน · รอบที่ปิดแล้ว ${all.length} รอบ · '
      'มัธยฐานหน่วยต่อรอบ ${units[units.length ~/ 2].toStringAsFixed(0)} kWh\n');
  stdout.write(report('ไฟฟ้า (ทุกบ้าน)', all, households: households));

  stdout.writeln('===== แยกตามความถี่การจดมิเตอร์ (MAPE เฉลี่ยทุกจุดวัด) =====');
  for (final e in byFrequency.entries) {
    if (e.value.isEmpty) continue;
    final k0 = overallMape(evaluate(e.value, 0));
    final k5 = overallMape(evaluate(e.value, 5));
    final best = bestWeight(e.value);
    stdout.writeln('จดทุก ${e.key} วัน (${e.value.length} รอบ): k=0 ${k0.toStringAsFixed(1)}% · '
        'k=5 ${k5.toStringAsFixed(1)}% · ดีที่สุด k=${best.toStringAsFixed(0)} '
        '${overallMape(evaluate(e.value, best)).toStringAsFixed(1)}%');
  }
}
