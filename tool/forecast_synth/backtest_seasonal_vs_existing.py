"""
สเต็ป 6: Backtest — เทียบวิธีเดิมในแอป (EnergyForecaster) กับวิธีใหม่
(seasonal curve ที่ผสม synthetic+จริง) ว่าอันไหนทายแม่นกว่า

ใช้ข้อมูลจริงเท่าที่ export มาได้ (real_*.csv) เท่านั้น เคสไหนข้อมูลจริง
ยังน้อยเกินไป (น้อยกว่า 4 เดือน) จะข้ามไปก่อน ไม่ error

วิธี backtest: เก็บ 2 เดือนล่าสุดของข้อมูลจริงไว้เป็น "holdout" (ไม่ให้
โมเดลเห็น) แล้วให้แต่ละวิธีทายเดือนเหล่านั้น จากนั้นเทียบกับค่าจริงที่
เกิดขึ้นแล้ว ด้วยค่า MAE (mean absolute error, ยิ่งน้อยยิ่งแม่น)

หมายเหตุสำคัญ: ตอนนี้มีข้อมูลจริงน้อยมาก (หลักเดือน ไม่ใช่หลักปี) ผลลัพธ์
เป็นแค่ตัวชี้วัดเบื้องต้น ไม่ใช่ข้อสรุปทางสถิติที่หนักแน่น ยิ่งมีข้อมูลจริง
มากขึ้นเรื่อยๆ (export บัญชีอื่นเพิ่ม / เวลาผ่านไป) ยิ่ง backtest นี้น่าเชื่อถือขึ้น
"""

import os
from blend_seasonal_curves import (
    CASES, read_csv_rows, normalized_monthly_curve, blend, K_TRUST_PRIOR,
)

MIN_MONTHS_FOR_BACKTEST = 4
N_HOLDOUT = 2


def moving_average_forecast(train_values):
    """เลียนแบบ EnergyForecaster.movingAverage แบบง่าย (ไม่มี remaining days
    เพราะ backtest นี้ทายทั้งเดือน ไม่ใช่ทายปลายรอบบิล) = ค่าเฉลี่ยของ training"""
    return sum(train_values) / len(train_values)


def linear_regression_forecast(train_values, forecast_index):
    """พอร์ตตรงจาก EnergyForecaster.linearRegression (สูตร OLS เดียวกัน)"""
    n = len(train_values)
    if n == 1:
        return train_values[0]
    sum_x = sum_y = sum_xy = sum_x2 = 0
    for i, y in enumerate(train_values):
        x = i + 1
        sum_x += x
        sum_y += y
        sum_xy += x * y
        sum_x2 += x * x
    denom = (n * sum_x2 - sum_x * sum_x)
    if denom == 0:
        return sum_y / n
    b = (n * sum_xy - sum_x * sum_y) / denom
    a = (sum_y - b * sum_x) / n
    forecast = a + b * forecast_index
    return max(forecast, 0)


def seasonal_curve_forecast(train_rows, synthetic_rows, target_month, value_key):
    """วิธีใหม่: seasonal curve ที่ fit จากเฉพาะ training rows (ไม่เห็น holdout)
    ผสมกับ synthetic แล้วเอา training mean x curve[target_month]"""
    prior_curve, _ = normalized_monthly_curve(synthetic_rows, value_key)
    real_curve, real_counts = normalized_monthly_curve(train_rows, value_key)
    final_curve = blend(prior_curve, real_curve, real_counts, k=K_TRUST_PRIOR)
    train_values = [r[value_key] for r in train_rows]
    train_mean = sum(train_values) / len(train_values)
    return train_mean * final_curve[target_month]


def backtest_case(case_info):
    real_rows = read_csv_rows(case_info["real_file"])
    synthetic_rows = read_csv_rows(case_info["synthetic_file"])

    real_rows.sort(key=lambda r: (r["year"], r["month"]))

    if len(real_rows) < MIN_MONTHS_FOR_BACKTEST:
        print(f"\n=== เคส {case_info['case_id']} ===")
        print(f"  ข้อมูลจริงมีแค่ {len(real_rows)} เดือน "
              f"(ต้องการอย่างน้อย {MIN_MONTHS_FOR_BACKTEST}) — ข้าม backtest ไปก่อน")
        return None

    train_rows = real_rows[:-N_HOLDOUT]
    holdout_rows = real_rows[-N_HOLDOUT:]

    print(f"\n=== เคส {case_info['case_id']} "
          f"(train={len(train_rows)} เดือน, holdout={len(holdout_rows)} เดือน) ===")

    for value_key, label in [("elec_units", "ไฟ"), ("water_units", "น้ำ")]:
        train_values = [r[value_key] for r in train_rows]

        errors = {"moving_average": [], "linear_regression": [], "seasonal_curve": []}
        for i, holdout in enumerate(holdout_rows):
            actual = holdout[value_key]
            forecast_index = len(train_values) + i + 1

            pred_ma = moving_average_forecast(train_values)
            pred_lr = linear_regression_forecast(train_values, forecast_index)
            pred_sc = seasonal_curve_forecast(
                train_rows, synthetic_rows, holdout["month"], value_key)

            errors["moving_average"].append(abs(pred_ma - actual))
            errors["linear_regression"].append(abs(pred_lr - actual))
            errors["seasonal_curve"].append(abs(pred_sc - actual))

            print(f"  [{label}] {holdout['year']}-{holdout['month']:02d} "
                  f"จริง={actual:.1f}  "
                  f"moving_avg={pred_ma:.1f}(err={abs(pred_ma-actual):.1f})  "
                  f"linear_reg={pred_lr:.1f}(err={abs(pred_lr-actual):.1f})  "
                  f"seasonal_curve={pred_sc:.1f}(err={abs(pred_sc-actual):.1f})")

        print(f"  >> MAE เฉลี่ย [{label}]: "
              + ", ".join(f"{k}={sum(v)/len(v):.1f}" for k, v in errors.items()))

    return True


if __name__ == "__main__":
    ran_any = False
    for case_info in CASES:
        result = backtest_case(case_info)
        ran_any = ran_any or bool(result)

    if not ran_any:
        print("\nยังไม่มีเคสไหนมีข้อมูลจริงพอจะ backtest ได้เลย "
              f"(ต้องการอย่างน้อย {MIN_MONTHS_FOR_BACKTEST} เดือนต่อเคส) "
              "— export บัญชีจริงเพิ่ม หรือรอสะสมข้อมูลเพิ่มก่อนค่อยกลับมา backtest")
    else:
        print("\n--- สรุป ---")
        print("MAE ยิ่งน้อยยิ่งแม่น เทียบ 3 วิธีข้างบนแล้วเลือกวิธีที่ error ต่ำสุด "
              "ไปใช้จริงในแอปได้เลย (ข้อมูลยังน้อย ผลลัพธ์เป็นแค่แนวโน้มเบื้องต้น)")