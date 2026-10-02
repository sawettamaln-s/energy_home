"""
วัดความแม่นยำของวิธีคาดการณ์ "เดือนถัดไป" ที่แอปใช้ กับข้อมูลจริง
(สถิติภาคที่อยู่อาศัยรายเดือนชุดเดียวกับ build_seasonal_curves.py)

วิธีทดสอบ: แบ่งข้อมูลตามเวลา (time-based holdout) ไม่ให้ข้อมูลอนาคตรั่วเข้า
  - ช่วงฝึก (สร้าง seasonal curve): 2016-2022 ไม่รวม 2020-2021
  - ช่วงทดสอบ: ทุกเดือนตั้งแต่ ม.ค. 2023 ถึงเดือนล่าสุดที่มีข้อมูล
  แต่ละเดือนทดสอบ ให้แต่ละวิธีทายจากข้อมูลก่อนหน้าเดือนนั้นเท่านั้น
  (walk-forward / one-step-ahead) แล้วเทียบกับค่าจริง

วิธีที่เทียบ (สูตรเดียวกับ lib/utils/forecaster.dart):
  - seasonal : เฉลี่ย 3 เดือนล่าสุดหลังหักฤดูกาล x ตัวคูณของเดือนเป้าหมาย
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
TEST_FROM = (2023, 1)


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


def evaluate(series):
    curve = seasonal_index(series, TRAIN_YEARS)
    keys = sorted(series)
    errors = {'seasonal': [], 'linear': [], 'naive': []}
    for i, key in enumerate(keys):
        if key < TEST_FROM or i < 12:
            continue
        actual = series[key]
        history = [series[k] for k in keys[:i]]
        last3_keys = keys[i - 3:i]
        preds = {
            'seasonal': seasonal_forecast([series[k] for k in last3_keys],
                                          [k[1] for k in last3_keys], curve, key[1]),
            'linear': linear_forecast(history[-12:]),
            'naive': history[-1],
        }
        for method, pred in preds.items():
            errors[method].append(abs(pred - actual) / actual * 100)
    return {m: sum(e) / len(e) for m, e in errors.items()}, len(errors['naive'])


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    print('MAPE ของการคาดการณ์เดือนถัดไป (ช่วงทดสอบ ม.ค. 2023 เป็นต้นไป)\n')
    for name, file in SERIES_FILES.items():
        result, n = evaluate(read_series(file))
        print(f'{name} ({n} เดือนทดสอบ)')
        for method in ('seasonal', 'linear', 'naive'):
            mape = result[method]
            print(f'  {method:9} MAPE = {mape:5.2f}%  ({lewis_label(mape)})')
        print()


if __name__ == '__main__':
    main()
