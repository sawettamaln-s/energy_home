"""
เคส 2: กรุงเทพ มิเตอร์ TOU + น้ำ

ใช้ climate/seasonal profile เดียวกับเคส 1 (ภูมิอากาศเดียวกัน)
เพิ่ม: แบ่งครัวเรือนเป็น 2 กลุ่มพฤติกรรม
  - optimizer (~40%): ย้ายการใช้ไฟไป off-peak จริง (เช่น ตั้งเวลาซักผ้า/ทำน้ำอุ่นกลางคืน)
  - non-optimizer (~60%): เปลี่ยนมิเตอร์เป็น TOU แต่ใช้ไฟตามชีวิตประจำวันปกติ
"""

import numpy as np
from common import (
    cooling_degree_index, seasonal_factor_from_degree_index,
    generate_series_for_household, write_csv, print_monthly_summary,
    month_index_to_ym,
)

N_HOUSEHOLDS = 150
N_MONTHS = 30
START_YEAR, START_MONTH = 2024, 3

BANGKOK_MEAN_TEMP_C = np.array([
    27.6, 28.7, 29.8, 30.8, 30.5, 29.8,
    29.3, 29.1, 28.7, 28.5, 28.4, 27.4,
])
_degree_index = cooling_degree_index(BANGKOK_MEAN_TEMP_C)

SEASONAL_FACTOR_ELEC = seasonal_factor_from_degree_index(_degree_index, base_fraction=0.55)
SEASONAL_FACTOR_WATER = seasonal_factor_from_degree_index(_degree_index, base_fraction=0.85)


def sample_base_level_elec(n, rng):
    # คนกทม.ที่เลือก TOU มักใช้ไฟสูงกว่าค่าเฉลี่ยเคส 1 เล็กน้อย (คุ้มกว่าถ้าใช้เยอะ)
    return rng.lognormal(mean=np.log(420), sigma=0.45, size=n)


def sample_base_level_water(n, rng):
    return rng.lognormal(mean=np.log(15), sigma=0.35, size=n)


OPTIMIZER_PROB = 0.40
OFFPEAK_RATIO_OPTIMIZER = (0.65, 0.78)
OFFPEAK_RATIO_NON_OPTIMIZER = (0.35, 0.48)


def generate_case2_dataset(n_households=N_HOUSEHOLDS, n_months=N_MONTHS, seed=43):
    rng = np.random.default_rng(seed)
    elec_base_all = sample_base_level_elec(n_households, rng)
    water_base_all = sample_base_level_water(n_households, rng)
    is_optimizer = rng.random(n_households) < OPTIMIZER_PROB

    rows = []
    for h in range(n_households):
        elec_series = generate_series_for_household(
            elec_base_all[h], SEASONAL_FACTOR_ELEC, n_months, START_YEAR, START_MONTH, rng)
        water_series = generate_series_for_household(
            water_base_all[h], SEASONAL_FACTOR_WATER, n_months, START_YEAR, START_MONTH, rng)

        lo, hi = OFFPEAK_RATIO_OPTIMIZER if is_optimizer[h] else OFFPEAK_RATIO_NON_OPTIMIZER
        base_offpeak_ratio = rng.uniform(lo, hi)

        for i in range(n_months):
            year, month = month_index_to_ym(START_YEAR, START_MONTH, i)
            offpeak_ratio = np.clip(base_offpeak_ratio + rng.normal(0, 0.04), 0.1, 0.9)
            total_elec = elec_series[i]
            offpeak_units = total_elec * offpeak_ratio
            onpeak_units = total_elec - offpeak_units

            rows.append({
                "household_id": f"case2_{h:04d}",
                "case": "bangkok_tou",
                "year": year,
                "month": month,
                "is_optimizer": bool(is_optimizer[h]),
                "elec_units_onpeak": round(onpeak_units, 1),
                "elec_units_offpeak": round(offpeak_units, 1),
                "water_units": round(water_series[i], 1),
            })
    return rows


if __name__ == "__main__":
    rows = generate_case2_dataset()
    write_csv(rows, "case2_bangkok_tou.csv")
    print(f"เขียนไฟล์ case2_bangkok_tou.csv แล้ว: {len(rows)} แถว "
          f"({N_HOUSEHOLDS} households x {N_MONTHS} เดือน)")

    n_opt = sum(1 for r in rows if r["is_optimizer"]) / N_MONTHS
    print(f"จำนวนบ้าน optimizer: {n_opt:.0f} / {N_HOUSEHOLDS} ({n_opt / N_HOUSEHOLDS:.0%})")

    for r in rows[:6]:
        total = r["elec_units_onpeak"] + r["elec_units_offpeak"]
        print(f"  {r['year']}-{r['month']:02d} optimizer={r['is_optimizer']}: "
              f"onpeak={r['elec_units_onpeak']} offpeak={r['elec_units_offpeak']} "
              f"(offpeak%={r['elec_units_offpeak']/total:.0%})")

    for r in rows:
        r["elec_units_total"] = r["elec_units_onpeak"] + r["elec_units_offpeak"]
    print_monthly_summary(rows, "elec_units_total", "ไฟรวม (onpeak+offpeak)")
