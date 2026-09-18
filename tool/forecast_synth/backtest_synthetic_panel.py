"""
Backtest ที่ใช้ synthetic panel "ทั้งหมด" (150-300 บ้าน x ~30 เดือน/เคส, ครบทั้ง 4
เคส) แทนที่จะพึ่งข้อมูลจริงที่มีแค่ 8 แถว (real_bangkok_normal.csv) แบบที่
backtest_seasonal_vs_existing.py เดิมทำ — ตัวเดิมทดสอบได้แค่ 1 ใน 4 เคส และ
holdout ดันตรงกับ 2 เดือนที่ข้อมูลจริงผิดปกติ (บิลรอบที่ยังไม่ปิดสมบูรณ์) ทำให้
MAE ทุกวิธีคลาดเคลื่อนสูงเกินจริงและไม่มีความหมาย

วิธีคิดของสคริปต์นี้: ปฏิบัติกับ synthetic household 1 หลังเหมือนเป็น "ผู้ใช้จริง
1 คน" ที่มีประวัติของตัวเอง 30 เดือน แบ่งเป็น
  - train   = ทุกเดือนยกเว้น N_HOLDOUT เดือนสุดท้าย
  - holdout = N_HOLDOUT เดือนสุดท้าย (ค่าที่ "จริง" ให้แต่ละวิธีทาย)

prior curve ต่อเคสสร้างจาก "เฉพาะ train rows ของทุกบ้านในเคสนั้น" (ไม่รวม
holdout เดือนไหนของบ้านไหนเลย กัน leakage) ส่วน real curve ที่เอาไป blend กับ
prior ต่อบ้าน สร้างจาก train rows ของบ้านนั้นเอง (เหมือนที่แอปจริงทำกับประวัติ
ของผู้ใช้ 1 คน) — ทำซ้ำแบบนี้ทุกบ้าน ทุกเคส แล้วรวม error ข้ามบ้านทั้งหมด

ผลคือได้ MAE จากจุดทดสอบหลักร้อยต่อเคส ครบทั้ง 4 เคส แทนที่จะมีแค่ 2 จุดทดสอบ
ในเคสเดียวแบบก่อนหน้า
"""
from collections import defaultdict

from blend_seasonal_curves import (
    CASES,
    K_TRUST_PRIOR,
    blend,
    normalized_monthly_curve,
    read_csv_rows,
)

N_HOLDOUT = 2


def moving_average_forecast(train_values):
    """เลียนแบบ EnergyForecaster.movingAverage แบบง่าย = ค่าเฉลี่ยของ training"""
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
    denom = n * sum_x2 - sum_x * sum_x
    if denom == 0:
        return sum_y / n
    b = (n * sum_xy - sum_x * sum_y) / denom
    a = (sum_y - b * sum_x) / n
    return max(a + b * forecast_index, 0)


def group_by_household(rows):
    groups = defaultdict(list)
    for r in rows:
        groups[r["household_id"]].append(r)
    for hid in groups:
        groups[hid].sort(key=lambda r: (r["year"], r["month"]))
    return groups


def backtest_case_full_panel(case_info):
    synthetic_rows = read_csv_rows(case_info["synthetic_file"])
    households = group_by_household(synthetic_rows)

    for value_key, label in [("elec_units", "ไฟ"), ("water_units", "น้ำ")]:
        # แยก train/holdout ต่อบ้านก่อน แล้วเอา train ของ "ทุกบ้าน" มารวมเป็น
        # prior เดียวของเคสนี้ (ไม่ให้ holdout เดือนไหนของบ้านไหนหลุดเข้า prior)
        all_train_rows = []
        household_splits = {}
        for hid, rows in households.items():
            if len(rows) <= N_HOLDOUT:
                continue
            train_rows = rows[:-N_HOLDOUT]
            holdout_rows = rows[-N_HOLDOUT:]
            household_splits[hid] = (train_rows, holdout_rows)
            all_train_rows.extend(train_rows)

        prior_curve, _ = normalized_monthly_curve(all_train_rows, value_key)

        errors = {"moving_average": [], "linear_regression": [], "seasonal_curve": []}
        for train_rows, holdout_rows in household_splits.values():
            train_values = [r[value_key] for r in train_rows]
            train_mean = sum(train_values) / len(train_values)

            real_curve, real_counts = normalized_monthly_curve(train_rows, value_key)
            final_curve = blend(prior_curve, real_curve, real_counts, k=K_TRUST_PRIOR)

            for i, holdout in enumerate(holdout_rows):
                actual = holdout[value_key]
                forecast_index = len(train_values) + i + 1

                pred_ma = moving_average_forecast(train_values)
                pred_lr = linear_regression_forecast(train_values, forecast_index)
                pred_sc = train_mean * final_curve[holdout["month"]]

                errors["moving_average"].append(abs(pred_ma - actual))
                errors["linear_regression"].append(abs(pred_lr - actual))
                errors["seasonal_curve"].append(abs(pred_sc - actual))

        n_points = len(errors["moving_average"])
        mae_str = ", ".join(
            f"{k}_MAE={sum(v) / len(v):.2f}" for k, v in errors.items()
        )
        print(f"  [{label}] บ้าน={len(household_splits)}  จุดทดสอบ={n_points}  {mae_str}")


if __name__ == "__main__":
    for case_info in CASES:
        print(
            f"\n=== เคส {case_info['case_id']} (synthetic panel เต็มจำนวน, "
            f"holdout {N_HOLDOUT} เดือนท้ายสุดของแต่ละบ้าน) ==="
        )
        backtest_case_full_panel(case_info)

    print("\n--- สรุป ---")
    print(
        "MAE ชุดนี้มาจากข้อมูล synthetic ทั้ง 4 เคสเต็มจำนวน (150-300 บ้าน x "
        "~2.5 ปี/บ้าน) ครบทุกเคส ไม่ใช่ข้อมูลจริง 8 แถวที่มีแค่ 1 เคสแบบก่อนหน้า — "
        "ใช้แสดงว่า 3 วิธีต่างกันแค่ไหนเมื่อมีข้อมูลมากพอและสะอาด ส่วนความแม่นกับ"
        "ผู้ใช้จริงยังต้องอาศัยข้อมูลจริงสะสมเพิ่มแยกต่างหาก (ดู "
        "backtest_seasonal_vs_existing.py สำหรับผลกับข้อมูลจริงเท่าที่มี)"
    )