"""
เคส 4: ต่างจังหวัด มิเตอร์ TOU + น้ำ

เคสนี้ในข้อมูลจริงมักมีตัวอย่างน้อยที่สุดใน 4 เคส เพราะ TOU ในต่างจังหวัด
ไม่ค่อยเป็นที่นิยม (ส่วนใหญ่เลือกเพราะมีโหลดสูงเฉพาะจุด เช่น เครื่องสูบน้ำเกษตร)
เลยตั้ง N_HOUSEHOLDS ให้น้อยกว่าเคสอื่น และ base_level สูงกว่าเคส 3
"""

import numpy as np
from common import (
    generate_series_for_household, write_csv, print_monthly_summary,
    month_index_to_ym,
)

N_HOUSEHOLDS = 60  # น้อยกว่าเคสอื่น เพราะกลุ่มนี้เล็กกว่าจริง
N_MONTHS = 30
START_YEAR, START_MONTH = 2024, 3

# climate profile เดียวกับเคส 3
UPCOUNTRY_MEAN_TEMP_C = np.array([
    22.5, 24.0, 27.0, 30.0, 29.5, 29.0,
    28.5, 28.0, 27.5, 26.5, 24.0, 21.5,
])
COOLING_THRESHOLD_C = 24.0
_degree = np.clip(UPCOUNTRY_MEAN_TEMP_C - COOLING_THRESHOLD_C, 0, None)
_degree_index = _degree / _degree.mean()

SEASONAL_FACTOR_WATER = 0.90 + 0.10 * _degree_index
SEASONAL_FACTOR_WATER = SEASONAL_FACTOR_WATER / SEASONAL_FACTOR_WATER.mean()


def household_elec_seasonal_factor(base_fraction: float) -> np.ndarray:
    variable_fraction = 1.0 - base_fraction
    factor = base_fraction + variable_fraction * _degree_index
    return factor / factor.mean()


def sample_base_level_elec(n, rng):
    # คนต่างจังหวัดที่เลือก TOU มักใช้ไฟสูงกว่าเคส 3 มาก (โหลดเฉพาะจุด เช่น ปั๊มน้ำ/เครื่องจักรเล็กๆ)
    return rng.lognormal(mean=np.log(480), sigma=0.55, size=n)


def sample_base_level_water(n, rng):
    return rng.lognormal(mean=np.log(10), sigma=0.55, size=n)


# กลุ่ม TOU ต่างจังหวัดมักพึ่งพาแอร์น้อยกว่าเคส 3 เฉลี่ย (โหลดหลักมาจากอย่างอื่น ไม่ใช่แอร์บ้าน)
AC_RELIANCE_RANGE = (0.65, 0.95)

OPTIMIZER_PROB = 0.35
OFFPEAK_RATIO_OPTIMIZER = (0.60, 0.75)
OFFPEAK_RATIO_NON_OPTIMIZER = (0.30, 0.45)


def generate_case4_dataset(n_households=N_HOUSEHOLDS, n_months=N_MONTHS, seed=45):
    rng = np.random.default_rng(seed)
    elec_base_all = sample_base_level_elec(n_households, rng)
    water_base_all = sample_base_level_water(n_households, rng)
    ac_base_fraction_all = rng.uniform(*AC_RELIANCE_RANGE, size=n_households)
    is_optimizer = rng.random(n_households) < OPTIMIZER_PROB

    rows = []
    for h in range(n_households):
        seasonal_factor_elec_h = household_elec_seasonal_factor(ac_base_fraction_all[h])

        elec_series = generate_series_for_household(
            elec_base_all[h], seasonal_factor_elec_h, n_months, START_YEAR, START_MONTH, rng)
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
                "household_id": f"case4_{h:04d}",
                "case": "upcountry_tou",
                "year": year,
                "month": month,
                "is_optimizer": bool(is_optimizer[h]),
                "elec_units_onpeak": round(onpeak_units, 1),
                "elec_units_offpeak": round(offpeak_units, 1),
                "water_units": round(water_series[i], 1),
            })
    return rows


if __name__ == "__main__":
    rows = generate_case4_dataset()
    write_csv(rows, "case4_upcountry_tou.csv")
    print(f"เขียนไฟล์ case4_upcountry_tou.csv แล้ว: {len(rows)} แถว "
          f"({N_HOUSEHOLDS} households x {N_MONTHS} เดือน)")

    for r in rows:
        r["elec_units_total"] = r["elec_units_onpeak"] + r["elec_units_offpeak"]
    print_monthly_summary(rows, "elec_units_total", "ไฟรวม (onpeak+offpeak)")
    print_monthly_summary(rows, "water_units", "น้ำ")
