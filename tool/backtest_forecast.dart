// สคริปต์ทดสอบความแม่นยำของ "คาดการณ์เดือนถัดไป" (Linear Regression)
// ด้วยวิธี walk-forward backtesting — ใช้สูตรเดียวกับที่แอปใช้จริงเป๊ะ ๆ
// (import EnergyForecaster.linearRegression ตรงจาก lib/utils/forecaster.dart
// ไม่ได้เขียนสูตรซ้ำ เพื่อให้ผลลัพธ์ตรงกับที่ผู้ใช้เห็นในแอปจริง)
//
// วิธีใช้:
// 1. เอาข้อมูลบิลย้อนหลังจริงของบัญชี (จาก Firestore console หรือหน้า
//    ตั้งค่า > ประวัติบิล ในแอป) มาใส่ในลิสต์ electricityCost / waterCost /
//    totalCost ด้านล่าง เรียงจาก "เดือนเก่าสุด -> ใหม่สุด"
// 2. รันคำสั่ง: dart run tool/backtest_forecast.dart
// 3. เอาตัวเลข MAE / RMSE / MAPE ที่พิมพ์ออกมา ไปอ้างอิงในเล่มวิทยานิพนธ์
//
// หมายเหตุ: backtest นี้ครอบคลุมเฉพาะ "คาดการณ์เดือนถัดไป/หลายเดือน"
// (Linear Regression บนยอดบิลรายเดือน) เท่านั้น ไม่ครอบคลุม "คาดการณ์
// สิ้นเดือนของรอบปัจจุบัน" (Moving Average) เพราะอันนั้นต้องใช้ log การใช้
// ไฟฟ้า/น้ำรายวันย้อนหลัง ซึ่งอยู่คนละ collection ใน Firestore (ต้อง export
// เพิ่มถ้าต้องการวัดตัวนี้ด้วยในอนาคต)

import 'dart:math';

import 'package:energy_home/utils/forecaster.dart';

void main() {
  // ===== ใส่ข้อมูลบิลย้อนหลังจริงตรงนี้ (เรียงเก่า -> ใหม่) =====
  final electricityCost = <double>[
    // ตัวอย่าง — แทนที่ด้วยยอดค่าไฟจริงรายเดือนจากบัญชีของคุณ
    850.0, 920.0, 1010.0, 980.0, 1105.0, 1230.0, 1180.0, 1290.0,
  ];
  final waterCost = <double>[
    120.0, 130.0, 125.0, 140.0, 135.0, 150.0, 145.0, 160.0,
  ];
  final totalCost = <double>[
    970.0, 1050.0, 1135.0, 1120.0, 1240.0, 1380.0, 1325.0, 1450.0,
  ];
  // ================================================================

  print('===== Backtest: คาดการณ์เดือนถัดไป (Linear Regression) =====\n');
  _runBacktest('ค่าไฟฟ้า', electricityCost);
  _runBacktest('ค่าน้ำ', waterCost);
  _runBacktest('ยอดรวม', totalCost);
}

void _runBacktest(String label, List<double> series) {
  if (series.length < 4) {
    print(
        '$label: ข้อมูลมีแค่ ${series.length} เดือน ต้องมีอย่างน้อย 4 เดือน '
        'ถึงจะ backtest ได้อย่างน้อย 2 รอบ (ข้าม)\n');
    return;
  }

  final actuals = <double>[];
  final predicted = <double>[];

  // walk-forward: เริ่ม train ที่ 2 เดือนแรก แล้วเลื่อนหน้าต่างไปทีละเดือน
  // ทุกรอบใช้ EnergyForecaster.linearRegression ตัวเดียวกับที่แอปเรียกจริง
  for (int i = 2; i < series.length; i++) {
    final train = series.sublist(0, i);
    final prediction = EnergyForecaster.linearRegression(
      monthlyValues: train,
      forecastMonth: train.length + 1,
    );
    actuals.add(series[i]);
    predicted.add(prediction);
  }

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
  final mape = mapeCount > 0 ? (sumPercentError / mapeCount) * 100 : double.nan;

  print('--- $label (backtest $n รอบ จากข้อมูล ${series.length} เดือน) ---');
  for (int j = 0; j < n; j++) {
    final err = actuals[j] - predicted[j];
    print('  รอบที่ ${j + 1}: จริง ${actuals[j].toStringAsFixed(2)} | '
        'คาดการณ์ ${predicted[j].toStringAsFixed(2)} | '
        'ผิดพลาด ${err.toStringAsFixed(2)}');
  }
  print('  MAE  (ค่าเฉลี่ยความคลาดเคลื่อนสัมบูรณ์): ${mae.toStringAsFixed(2)} บาท');
  print('  RMSE (Root Mean Squared Error):        ${rmse.toStringAsFixed(2)} บาท');
  print('  MAPE (% ความคลาดเคลื่อนเฉลี่ย):          ${mape.toStringAsFixed(1)}%');
  print('');
}