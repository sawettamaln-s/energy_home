// ignore_for_file: avoid_print
//
// สคริปต์ทดสอบความแม่นยำของ "คาดการณ์เดือนถัดไป" ด้วยวิธี walk-forward
// backtesting — เทียบ 2 วิธีที่แอปใช้จริงในไฟล์เดียวกัน:
//   1. Linear Regression  (fallback — ใช้เมื่อไม่รู้ area/meterType)
//   2. Seasonal Curve     (วิธีหลัก — ใช้เมื่อรู้ area/meterType)
//
// ทั้งสองวิธีเรียกฟังก์ชันตรงจาก lib/utils/forecaster.dart และดึง curve
// ตรงจาก lib/utils/seasonal_curves.dart เพื่อให้ผลลัพธ์ตรงกับที่ผู้ใช้เห็น
// ในแอปจริงเป๊ะๆ (ไม่ได้เขียนสูตรซ้ำ)
//
// วิธีใช้:
// 1. ตั้ง area/meterType ของบัญชีที่จะทดสอบด้านล่าง (ต้องตรงกับ
//    users/{uid}.area และ meterType จริงของบัญชีนั้น ไม่งั้น curve ที่ดึงมา
//    จะไม่ตรงเคส)
// 2. เอาบิลย้อนหลังจริง (เดือนปฏิทิน 1-12 + ยอดเงิน) มาใส่แทนตัวอย่าง ใน
//    electricity / water เรียงจาก "เดือนเก่าสุด -> ใหม่สุด" — ต้องใส่เดือน
//    ปฏิทินให้ตรงจริง เพราะ seasonal curve ใช้เดือนนี้คำนวณตัวคูณฤดูกาล
//    ถ้าใส่ผิดผลลัพธ์จะเพี้ยน ต้องมีอย่างน้อย 4 เดือนถึงจะ backtest ได้
// 3. รันคำสั่ง: dart run tool/backtest_forecast.dart
// 4. เอาตาราง MAE / RMSE / MAPE ของทั้ง 2 วิธี (พิมพ์ออกมาให้เทียบข้างกัน)
//    ไปอ้างอิงในเล่มวิทยานิพนธ์ — ใช้เป็นหลักฐานว่าวิธีไหนแม่นกว่าในข้อมูล
//    จริงของบัญชีนี้
//
// หมายเหตุ:
// - ครอบคลุมเฉพาะ "คาดการณ์เดือนถัดไป/หลายเดือน" เท่านั้น ไม่ครอบคลุม
//   "คาดการณ์สิ้นเดือนของรอบปัจจุบัน" (Moving Average) เพราะอันนั้นต้องใช้
//   log การใช้ไฟฟ้า/น้ำรายวันย้อนหลัง ซึ่งอยู่คนละ collection ใน Firestore
// - ไม่ backtest "ยอดรวม" (ไฟฟ้า+น้ำ) แยกต่างหาก เพราะ seasonal curve
//   แยกเป็นคนละชุดสำหรับไฟฟ้ากับน้ำ ไม่มี curve รวม — ดูผลแยกทีละรายการแทน

import 'dart:math';

import 'package:energy_home/utils/forecaster.dart';
import 'package:energy_home/utils/seasonal_curves.dart';

/// จุดข้อมูลบิล 1 เดือน: (เดือนปฏิทิน 1-12, ยอดเงิน)
typedef MonthlyPoint = (int month, double value);

void main() {
  // ===== ตั้งค่าบัญชีที่จะทดสอบ ให้ตรงกับ users/{uid} จริง =====
  const area = 'bangkok'; // 'bangkok' หรือ 'province'
  const meterType = 'normal'; // 'normal' หรือ 'tou'

  // ===== ใส่ข้อมูลบิลย้อนหลังจริงตรงนี้ (เรียงเก่า -> ใหม่) =====
  // ตัวอย่าง: ม.ค.=850, ก.พ.=920, ... — แทนที่ด้วยข้อมูลจริงจากบัญชีคุณ
  final electricity = <MonthlyPoint>[
    (1, 850.0), (2, 920.0), (3, 1010.0), (4, 980.0), (5, 1105.0),
    (6, 1230.0), (7, 1180.0), (8, 1290.0),
  ];
  final water = <MonthlyPoint>[
    (1, 120.0), (2, 130.0), (3, 125.0), (4, 140.0), (5, 135.0),
    (6, 150.0), (7, 145.0), (8, 160.0),
  ];
  // ================================================================

  print('===== Backtest: คาดการณ์เดือนถัดไป (Linear Regression vs Seasonal Curve) =====');
  print('บัญชีทดสอบ: area=$area, meterType=$meterType\n');

  _runComparison(
    'ค่าไฟฟ้า',
    electricity,
    curve: _resolveCurve(area, meterType, isWater: false),
  );
  _runComparison(
    'ค่าน้ำ',
    water,
    curve: _resolveCurve(area, meterType, isWater: true),
  );
}

// เหมือน _resolveCurve ใน lib/services/analysis_service.dart เป๊ะๆ
List<double>? _resolveCurve(String area, String meterType,
    {required bool isWater}) {
  final caseKey = SeasonalCurves.caseKeyFor(area: area, meterType: meterType);
  final curveMap = isWater ? SeasonalCurves.water : SeasonalCurves.elec;
  return curveMap[caseKey];
}

void _runComparison(
  String label,
  List<MonthlyPoint> series, {
  required List<double>? curve,
}) {
  if (series.length < 4) {
    print('$label: ข้อมูลมีแค่ ${series.length} เดือน '
        'ต้องมีอย่างน้อย 4 เดือน (ข้าม)\n');
    return;
  }

  final months = series.map((p) => p.$1).toList();
  final values = series.map((p) => p.$2).toList();

  print('=== $label (${series.length} เดือนของข้อมูล) ===\n');

  // ----- วิธีที่ 1: Linear Regression -----
  final lrActuals = <double>[];
  final lrPredicted = <double>[];
  for (int i = 2; i < values.length; i++) {
    final train = values.sublist(0, i);
    final prediction = EnergyForecaster.linearRegression(
      monthlyValues: train,
      forecastMonth: train.length + 1,
    );
    lrActuals.add(values[i]);
    lrPredicted.add(prediction);
  }
  _printRounds('Linear Regression', lrActuals, lrPredicted);
  final lrMetrics = _metrics(lrActuals, lrPredicted);
  _printMetrics('Linear Regression', lrMetrics, lrActuals.length);
  print('');

  // ----- วิธีที่ 2: Seasonal Curve -----
  if (curve == null) {
    print('  [Seasonal Curve] ไม่มี curve ตรงกับ area/meterType นี้ (ข้าม)\n');
    return;
  }

  final scActuals = <double>[];
  final scPredicted = <double>[];
  // เลียนแบบ _recentWindow ใน analysis_service.dart: ใช้ 3 เดือนล่าสุดก่อน
  // จุดที่จะทาย (หรือเท่าที่มีถ้าน้อยกว่า 3) เป็น "ระดับการใช้ปัจจุบัน"
  for (int i = 3; i < values.length; i++) {
    final windowStart = max(0, i - 3);
    final recentValues = values.sublist(windowStart, i);
    final recentMonths = months.sublist(windowStart, i);
    final targetMonth = months[i];
    final prediction = EnergyForecaster.seasonalForecast(
      recentMonthlyValues: recentValues,
      recentMonths: recentMonths,
      curve: curve,
      forecastMonth: targetMonth,
    );
    scActuals.add(values[i]);
    scPredicted.add(prediction);
  }

  if (scActuals.isEmpty) {
    print('  [Seasonal Curve] ข้อมูลไม่พอให้มี recent window 3 เดือน '
        'ก่อนจุดที่จะทายอย่างน้อย 1 รอบ (ข้าม)\n');
    return;
  }

  _printRounds('Seasonal Curve', scActuals, scPredicted);
  final scMetrics = _metrics(scActuals, scPredicted);
  _printMetrics('Seasonal Curve', scMetrics, scActuals.length);

  // ----- สรุปว่าวิธีไหนแม่นกว่า (เทียบด้วย MAE) -----
  final betterMethod =
      scMetrics.mae < lrMetrics.mae ? 'Seasonal Curve' : 'Linear Regression';
  final diff = (lrMetrics.mae - scMetrics.mae).abs();
  print('  สรุป: $betterMethod แม่นกว่า '
      '(MAE ต่างกัน ${diff.toStringAsFixed(2)} บาท)\n');
}

class _Metrics {
  final double mae;
  final double rmse;
  final double mape;
  _Metrics(this.mae, this.rmse, this.mape);
}

_Metrics _metrics(List<double> actuals, List<double> predicted) {
  double sumAbsError = 0;
  double sumSquaredError = 0;
  double sumPercentError = 0;
  int mapeCount = 0;

  for (int j = 0; j < actuals.length; j++) {
    final error = actuals[j] - predicted[j];
    sumAbsError += error.abs();
    sumSquaredError += error * error;
    if (actuals[j] != 0) {
      sumPercentError += (error.abs() / actuals[j]);
      mapeCount++;
    }
  }

  final n = actuals.length;
  final mae = sumAbsError / n;
  final rmse = sqrt(sumSquaredError / n);
  final mape =
      mapeCount > 0 ? (sumPercentError / mapeCount) * 100 : double.nan;
  return _Metrics(mae, rmse, mape);
}

void _printRounds(
    String methodName, List<double> actuals, List<double> predicted) {
  print('  --- $methodName: รายรอบ ---');
  for (int j = 0; j < actuals.length; j++) {
    final err = actuals[j] - predicted[j];
    print('    รอบที่ ${j + 1}: จริง ${actuals[j].toStringAsFixed(2)} | '
        'คาดการณ์ ${predicted[j].toStringAsFixed(2)} | '
        'ผิดพลาด ${err.toStringAsFixed(2)}');
  }
}

void _printMetrics(String methodName, _Metrics m, int rounds) {
  print('  [$methodName] สรุป ($rounds รอบ)');
  print('    MAE  (ค่าเฉลี่ยความคลาดเคลื่อนสัมบูรณ์): ${m.mae.toStringAsFixed(2)} บาท');
  print('    RMSE (Root Mean Squared Error):        ${m.rmse.toStringAsFixed(2)} บาท');
  print('    MAPE (% ความคลาดเคลื่อนเฉลี่ย):          ${m.mape.toStringAsFixed(1)}%');
}