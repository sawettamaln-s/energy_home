"""
วัดความแม่นยำของวิธีคาดการณ์ "เดือนถัดไป" ที่แอปใช้ กับข้อมูลจริง
(สถิติภาคที่อยู่อาศัยรายเดือนชุดเดียวกับ build_seasonal_curves.py)

วิธีทดสอบ: แบ่งข้อมูลตามเวลา (time-based holdout) ไม่ให้ข้อมูลอนาคตรั่วเข้า
  - ช่วงฝึก (สร้าง seasonal curve): 2016-2022 ไม่รวม 2020-2021
  - ช่วงทดสอบ: ทุกเดือนตั้งแต่ ม.ค. 2023 ถึงเดือนล่าสุดที่มีข้อมูล
  - น้ำภูมิภาค (กปภ. มีข้อมูลตั้งแต่ 2022): ฝึก 2022-2023 ทดสอบตั้งแต่ ม.ค. 2024
    และเทียบเพิ่มกับการยืมรูปแบบของ กปน. (seasonal-mwa) เพื่อยืนยันว่ารูปแบบ
    ของภูมิภาคเองแม่นกว่า
  แต่ละเดือนทดสอบ ให้แต่ละวิธีทายจากข้อมูลก่อนหน้าเดือนนั้นเท่านั้น
  (walk-forward / one-step-ahead) แล้วเทียบกับค่าจริง

วิธีที่เทียบ (สูตรเดียวกับ lib/utils/forecaster.dart):
  - seasonal : เดือนล่าสุด (RECENT_MONTHS = EnergyForecaster.seasonalRecentMonths)
               หลังหักฤดูกาล x ตัวคูณของเดือนเป้าหมาย
  - linear   : เส้นถดถอยเชิงเส้นจาก 12 เดือนล่าสุด (วิธีสำรองของแอป)
  - naive    : ใช้ค่าเดือนล่าสุดตรงๆ (เกณฑ์พื้นฐานสำหรับเทียบ)

ตัวชี้วัด: MAPE (Mean Absolute Percentage Error) — แปลผลตาม Lewis (1982)
  < 10% แม่นยำสูง | 10-20% ดี | 20-50% พอใช้ | > 50% ไม่แม่นยำ

ข้อควรรู้: ข้อมูลรวมทั้งภาคเรียบกว่าบ้านหลังเดียวมาก ค่า MAPE ที่ได้จึงเป็น
"ความแม่นยำของรูปแบบฤดูกาล" ไม่ใช่ความแม่นยำต่อบ้านแต่ละหลัง — ความแม่นยำ
ต่อบ้านจริงวัดด้วย tool/backtest_forecast.dart กับบิลของผู้ใช้

วิธีใช้: python tool/seasonal_curves/backtest_forecast_methods.py
"""

import sys

from build_seasonal_curves import SERIES_FILES, read_series, seasonal_index

TRAIN_YEARS = [y for y in range(2016, 2023) if y not in (2020, 2021)]
# จำนวนเดือนล่าสุดที่ใช้หาระดับการใช้ ต้องตรงกับ EnergyForecaster.seasonalRecentMonths
RECENT_MONTHS = 1
TEST_FROM = (2023, 1)

# ชุดข้อมูลที่เริ่มช้ากว่า ใช้ช่วงฝึก/ทดสอบของตัวเอง
SPLITS = {
    'water_upcountry': ([2022, 2023], (2024, 1)),
}


def seasonal_forecast(recent_values, recent_months, curve, target_month):
    deseasonalized = [v / curve[m - 1] for v, m in zip(recent_values, recent_months)]
    return sum(deseasonalized) / len(deseasonalized) * curve[target_month - 1]


def linear_forecast(values):
    n = len(values)
    xs = range(1, n + 1)
    sx, sy = sum(xs), sum(values)
    sxy = sum(x * y for x, y in zip(xs, values))
    sx2 = sum(x * x for x in xs)
    b = (n * sxy - sx * sy) / (n * sx2 - sx * sx)
    a = (sy - b * sx) / n
    return max(a + b * (n + 1), 0)


def lewis_label(mape):
    if mape < 10:
        return 'แม่นยำสูง'
    if mape < 20:
        return 'ดี'
    if mape < 50:
        return 'พอใช้'
    return 'ไม่แม่นยำ'


def evaluate(series, train_years=TRAIN_YEARS, test_from=TEST_FROM, extra_curves=None):
    curve = seasonal_index(series, train_years)
    curves = {'seasonal': curve, **(extra_curves or {})}
    keys = sorted(series)
    errors = {**{m: [] for m in curves}, 'linear': [], 'naive': []}
    for i, key in enumerate(keys):
        if key < test_from or i < 12:
            continue
        actual = series[key]
        history = [series[k] for k in keys[:i]]
        recent_keys = keys[i - RECENT_MONTHS:i]
        preds = {
            **{m: seasonal_forecast([series[k] for k in recent_keys],
                                    [k[1] for k in recent_keys], c, key[1])
               for m, c in curves.items()},
            'linear': linear_forecast(history[-12:]),
            'naive': history[-1],
        }
        for method, pred in preds.items():
            errors[method].append(abs(pred - actual) / actual * 100)
    return {m: sum(e) / len(e) for m, e in errors.items()}, len(errors['naive'])


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    print('MAPE ของการคาดการณ์เดือนถัดไป (walk-forward)\n')
    mwa_curve = seasonal_index(read_series(SERIES_FILES['water_bangkok']), TRAIN_YEARS)
    for name, file in SERIES_FILES.items():
        train_years, test_from = SPLITS.get(name, (TRAIN_YEARS, TEST_FROM))
        extra = {'seasonal-mwa': mwa_curve} if name == 'water_upcountry' else None
        result, n = evaluate(read_series(file), train_years, test_from, extra)
        print(f'{name} ({n} เดือนทดสอบ ตั้งแต่ {test_from[1]}/{test_from[0]})')
        for method in result:
            mape = result[method]
            print(f'  {method:12} MAPE = {mape:5.2f}%  ({lewis_label(mape)})')
        print()


if __name__ == '__main__':
    main()
