"""
เคส 3: ต่างจังหวัด มิเตอร์ปกติ + น้ำ

ใช้ profile ภูมิอากาศแบบ "ภาคเหนือ/อีสาน" เป็นตัวแทน (มีฤดูหนาวชัดเจนกว่ากทม.)
ประมาณจากข้อมูลภูมิอากาศเชียงใหม่ทั่วไป (ไม่ใช่ climate normal ทางการ 30 ปีแบบเคส 1)
เพื่อจำลองว่าอากาศแกว่งกว้างกว่ากทม. (หนาวกว่าในหน้าหนาว ร้อนพอๆกันในหน้าร้อน)

ต่างจากกทม.: การมีแอร์/ใช้แอร์ไม่ universal เท่ากทม. เลยให้แต่ละบ้านมี
"ระดับพึ่งพาแอร์" (base_fraction) สุ่มต่อบ้าน แทนที่จะ fix ค่าเดียวทั้งเคส
"""

import numpy as np
from common import (
    generate_series_for_household, write_csv, print_monthly_summary,
    month_index_to_ym,
)

N_HOUSEHOLDS = 150
N_MONTHS = 30
START_YEAR, START_MONTH = 2024, 3

# อุณหภูมิเฉลี่ยรายเดือนโดยประมาณ แบบภาคเหนือ/อีสาน (หนาวเด่นชัดกว่ากทม. พ.ย.-ก.พ.)
UPCOUNTRY_MEAN_TEMP_C = np.array([
    22.5, 24.0, 27.0, 30.0, 29.5, 29.0,  # ม.ค.-มิ.ย.
    28.5, 28.0, 27.5, 26.5, 24.0, 21.5,  # ก.ค.-ธ.ค.
])
COOLING_THRESHOLD_C = 24.0  # ต่ำกว่ากทม. เล็กน้อย เพราะฤดูหนาวเย็นกว่าจริง
_degree = np.clip(UPCOUNTRY_MEAN_TEMP_C - COOLING_THRESHOLD_C, 0, None)
_degree_index = _degree / _degree.mean()

SEASONAL_FACTOR_WATER = 0.90 + 0.10 * _degree_index
SEASONAL_FACTOR_WATER = SEASONAL_FACTOR_WATER / SEASONAL_FACTOR_WATER.mean()


def household_elec_seasonal_factor(base_fraction: float) -> np.ndarray:
    variable_fraction = 1.0 - base_fraction
    factor = base_fraction + variable_fraction * _degree_index
    return factor / factor.mean()


def sample_base_level_elec(n, rng):
    # ต่างจังหวัดมี median ต่ำกว่ากทม. (บ้านเดี่ยวหลายหลังใช้แอร์น้อยกว่า/บางบ้านไม่มีแอร์เลย)
    return rng.lognormal(mean=np.log(260), sigma=0.55, size=n)


def sample_base_level_water(n, rng):
    # น้ำประปาต่างจังหวัด median ต่ำกว่ากทม. (บางบ้านมีบ่อ/น้ำฝนเสริม) variance สูงกว่า
    return rng.lognormal(mean=np.log(10), sigma=0.55, size=n)


AC_RELIANCE_RANGE = (0.55, 0.95)  # base_fraction สุ่มต่อบ้าน: ยิ่งสูง = พึ่งแอร์น้อย/ไม่มีแอร์


def generate_case3_dataset(n_households=N_HOUSEHOLDS, n_months=N_MONTHS, seed=44):
    rng = np.random.default_rng(seed)
    elec_base_all = sample_base_level_elec(n_households, rng)
    water_base_all = sample_base_level_water(n_households, rng)
    ac_base_fraction_all = rng.uniform(*AC_RELIANCE_RANGE, size=n_households)

    rows = []
    for h in range(n_households):
        seasonal_factor_elec_h = household_elec_seasonal_factor(ac_base_fraction_all[h])

        elec_series = generate_series_for_household(
            elec_base_all[h], seasonal_factor_elec_h, n_months, START_YEAR, START_MONTH, rng)
        water_series = generate_series_for_household(
            water_base_all[h], SEASONAL_FACTOR_WATER, n_months, START_YEAR, START_MONTH, rng)

        for i in range(n_months):
            year, month = month_index_to_ym(START_YEAR, START_MONTH, i)
            rows.append({
                "household_id": f"case3_{h:04d}",
                "case": "upcountry_normal",
                "year": year,
                "month": month,
                "elec_units": round(elec_series[i], 1),
                "water_units": round(water_series[i], 1),
            })
    return rows


if __name__ == "__main__":
    rows = generate_case3_dataset()
    write_csv(rows, "case3_upcountry_normal.csv")
    print(f"เขียนไฟล์ case3_upcountry_normal.csv แล้ว: {len(rows)} แถว "
          f"({N_HOUSEHOLDS} households x {N_MONTHS} เดือน)")

    for r in rows[:6]:
        print(f"  {r['year']}-{r['month']:02d}: elec={r['elec_units']}  water={r['water_units']}")

    print_monthly_summary(rows, "elec_units", "ไฟ")
    print_monthly_summary(rows, "water_units", "น้ำ")
