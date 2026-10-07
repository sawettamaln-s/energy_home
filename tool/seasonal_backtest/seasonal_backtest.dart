// แกนคำนวณของสคริปต์ทดลอง "เส้นฤดูกาลเฉพาะบ้าน" (tool/backtest_seasonal_personal.dart)
// เป็น Dart ล้วน ไม่แตะ Firebase จึงเทสได้ (test/seasonal_backtest_test.dart)
//
// คำถาม: การพยากรณ์บิลเดือนถัดไปของแอป (EnergyForecaster.seasonalForecast ด้วย
// เส้นฤดูกาลระดับภาค/ประเทศ) แม่นขึ้นไหม ถ้าผสมรูปแบบฤดูกาลของบ้านนั้นเองจากปีที่ผ่านมา
//
//   เส้นเฉพาะบ้าน u[m] = หน่วยของบ้านในเดือน m ÷ ค่าเฉลี่ย 12 เดือนล่าสุดของบ้าน
//   เส้นที่ใช้ b[m]   = (1 − w) × เส้นประเทศ[m] + w × u[m],  w = 1 ÷ (1 + λ)
//
// λ ใหญ่ = เชื่อเส้นประเทศมาก (λ = ∞ คือเส้นประเทศล้วน) การผสมทดลองบนวิธี
// 3 เดือนล่าสุด (วิธีของแอปตอนทดลอง) เลือก λ ด้วย
// cross-validation แบ่งตามบ้าน วัดผลด้วย MAPE / WAPE ของหน่วยที่ทาย

import 'package:energy_home/utils/forecaster.dart';

// หน่วยรายเดือนของบ้านหนึ่ง: key = ปี × 12 + (เดือน − 1)
typedef MonthlySeries = Map<int, double>;

int monthKey(int year, int month) => year * 12 + month - 1;
int monthOf(int key) => key % 12 + 1;

// เส้นฤดูกาลประเทศจากบ้านใน [households] ช่วง [fromKey]..[fromKey + 11] (12 เดือน)
// แต่ละบ้านเทียบกับค่าเฉลี่ย 12 เดือนของตัวเอง แล้วเฉลี่ยข้ามบ้าน ปรับให้เฉลี่ยเท่า 1
// คืน list 12 ค่า (index 0 = ม.ค.) แบบเดียวกับ SeasonalCurves ของแอป
List<double> nationalCurve(Iterable<MonthlySeries> households, int fromKey) {
  final sums = List<double>.filled(12, 0);
  var n = 0;
  for (final h in households) {
    final values = [for (var k = fromKey; k < fromKey + 12; k++) h[k]];
    if (values.any((v) => v == null)) continue;
    final mean = values.fold<double>(0, (a, v) => a + v!) / 12;
    if (mean <= 0) continue;
    for (var k = fromKey; k < fromKey + 12; k++) {
      sums[monthOf(k) - 1] += h[k]! / mean;
    }
    n++;
  }
  if (n == 0) return List<double>.filled(12, 1);
  final curve = [for (final s in sums) s / n];
  final avg = curve.reduce((a, b) => a + b) / 12;
  return [for (final c in curve) c / avg];
}

// เส้นเฉพาะบ้านจาก 12 เดือนก่อน [targetKey] — null ถ้าข้อมูลไม่ครบ 12 เดือน
List<double>? householdCurve(MonthlySeries h, int targetKey) {
  final from = targetKey - 12;
  final values = [for (var k = from; k < targetKey; k++) h[k]];
  if (values.any((v) => v == null)) return null;
  final mean = values.fold<double>(0, (a, v) => a + v!) / 12;
  if (mean <= 0) return null;
  final curve = List<double>.filled(12, 1);
  for (var k = from; k < targetKey; k++) {
    curve[monthOf(k) - 1] = h[k]! / mean;
  }
  return curve;
}

List<double> blend(List<double> national, List<double>? personal, double lambda) {
  if (personal == null || lambda.isInfinite) return national;
  final w = 1 / (1 + lambda);
  return [for (var i = 0; i < 12; i++) (1 - w) * national[i] + w * personal[i]];
}

// ทายหน่วยของเดือน [targetKey] ด้วยวิธีของแอป ([window] เดือนล่าสุด หักฤดูกาลแล้ว
// คูณกลับ) โดยใช้เส้น [curve] — null ถ้าเดือนก่อนหน้าไม่ครบ
double? seasonalPredict(MonthlySeries h, int targetKey, List<double> curve,
    {int window = EnergyForecaster.seasonalRecentMonths}) {
  final keys = [for (var k = targetKey - window; k < targetKey; k++) k];
  if (keys.any((k) => h[k] == null)) return null;
  return EnergyForecaster.seasonalForecast(
    recentMonthlyValues: [for (final k in keys) h[k]!],
    recentMonths: [for (final k in keys) monthOf(k)],
    curve: curve,
    forecastMonth: monthOf(targetKey),
  );
}

class Errors {
  double _absPct = 0;
  double _abs = 0;
  double _actual = 0;
  double _signedPct = 0;
  int n = 0;

  void add(double predicted, double actual) {
    _absPct += (predicted - actual).abs() / actual * 100;
    _signedPct += (predicted - actual) / actual * 100;
    _abs += (predicted - actual).abs();
    _actual += actual;
    n++;
  }

  void addAll(Errors other) {
    _absPct += other._absPct;
    _signedPct += other._signedPct;
    _abs += other._abs;
    _actual += other._actual;
    n += other.n;
  }

  double get mape => n == 0 ? double.nan : _absPct / n;
  double get wape => _actual == 0 ? double.nan : _abs / _actual * 100;
  double get bias => n == 0 ? double.nan : _signedPct / n;
}

// วิธีที่เทียบ — คืนค่าทาย หรือ null ถ้าข้อมูลไม่พอ
typedef Method = double? Function(MonthlySeries h, int targetKey);

Method lastMonth() => (h, t) => h[t - 1];
Method sameMonthLastYear() => (h, t) => h[t - 12];
Method appSeasonal(List<double> national, {int window = EnergyForecaster.seasonalRecentMonths}) =>
    (h, t) => seasonalPredict(h, t, national, window: window);
Method personalSeasonal(List<double> national, double lambda) =>
    (h, t) => seasonalPredict(h, t, blend(national, householdCurve(h, t), lambda), window: 3);

// วัดวิธี [m] กับบ้าน [households] ทุกเดือนเป้าหมาย [targets] — วัดเฉพาะเดือนที่
// "ทุกวิธี" ทายได้ ([eligible]) ให้เทียบกันบนชุดเดียวกัน
Errors score(Iterable<MonthlySeries> households, Iterable<int> targets, Method m,
    bool Function(MonthlySeries h, int t) eligible) {
  final e = Errors();
  for (final h in households) {
    for (final t in targets) {
      final actual = h[t];
      if (actual == null || !eligible(h, t)) continue;
      final p = m(h, t);
      if (p != null) e.add(p, actual);
    }
  }
  return e;
}

// เดือนที่ทุกวิธีทายได้: มีหน่วยจริง, 12 เดือนก่อนหน้าครบ (ใช้ทั้งเส้นเฉพาะบ้าน
// และเดือนเดียวกันปีก่อน)
bool fullHistory(MonthlySeries h, int t) {
  if (h[t] == null) return false;
  for (var k = t - 12; k < t; k++) {
    if (h[k] == null) return false;
  }
  return true;
}

const List<double> lambdaGrid = [0.25, 0.5, 1, 2, 4, 8, 16];
const List<int> windowGrid = [1, 2, 3, 4, 6];
