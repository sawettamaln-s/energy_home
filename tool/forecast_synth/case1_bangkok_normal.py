"""
เคส 1: กรุงเทพ มิเตอร์ปกติ + น้ำ
สเต็ป 1: พารามิเตอร์พื้นฐาน + seasonal factor

รันไฟล์นี้เพื่อดูตัวอย่าง base_level ที่สุ่มได้ และกราฟ seasonal factor
ยังไม่สร้างข้อมูล 24-36 เดือนเต็มรูปแบบ (สเต็ปถัดไป)
"""

import numpy as np

# ---------- ตั้งค่าพื้นฐาน ----------
np.random.seed(42)  # fix seed ไว้ก่อน เพื่อให้ผลลัพธ์ reproducible ตอนทดสอบ

N_HOUSEHOLDS = 150  # จำนวนบ้านสมมติในเคสนี้

# อุณหภูมิเฉลี่ยรายเดือนกรุงเทพฯ (ค่าปกติ climate normal, องศาเซลเซียส)
# แหล่งอ้างอิง: JMA climate normals สถานีกรุงเทพฯ
BANGKOK_MEAN_TEMP_C = np.array([
    27.6, 28.7, 29.8, 30.8, 30.5, 29.8,  # ม.ค.-มิ.ย.
    29.3, 29.1, 28.7, 28.5, 28.4, 27.4,  # ก.ค.-ธ.ค.
])

# แปลงเป็น cooling-degree index: ยิ่งร้อนกว่า threshold ยิ่งมีค่าสูง
# threshold 26C คือจุดที่คนเริ่มเปิดแอร์บ่อยขึ้นอย่างมีนัยสำคัญ
COOLING_THRESHOLD_C = 26.0
_degree = np.clip(BANGKOK_MEAN_TEMP_C - COOLING_THRESHOLD_C, 0, None)
_degree_index = _degree / _degree.mean()  # normalize เฉลี่ยรายปี = 1.0

# สัดส่วนโหลดที่ผันตามฤดูกาล (แอร์) vs โหลดคงที่ทั้งปี (ตู้เย็น/ไฟ/เครื่องทำน้ำอุ่น ฯลฯ)
BASE_LOAD_FRACTION_ELEC = 0.55
VARIABLE_LOAD_FRACTION_ELEC = 1.0 - BASE_LOAD_FRACTION_ELEC

SEASONAL_FACTOR_ELEC = BASE_LOAD_FRACTION_ELEC + VARIABLE_LOAD_FRACTION_ELEC * _degree_index
SEASONAL_FACTOR_ELEC = SEASONAL_FACTOR_ELEC / SEASONAL_FACTOR_ELEC.mean()  # renormalize เฉลี่ย = 1.0

# น้ำผันตามฤดูกาลน้อยกว่าไฟมาก (คนกทม.ใช้น้ำอาบ/ล้างค่อนข้างคงที่ทั้งปี)
# ใช้ cooling-degree index ตัวเดียวกัน แต่ variable_fraction ต่ำกว่าไฟมาก
BASE_LOAD_FRACTION_WATER = 0.85
VARIABLE_LOAD_FRACTION_WATER = 1.0 - BASE_LOAD_FRACTION_WATER

SEASONAL_FACTOR_WATER = BASE_LOAD_FRACTION_WATER + VARIABLE_LOAD_FRACTION_WATER * _degree_index
SEASONAL_FACTOR_WATER = SEASONAL_FACTOR_WATER / SEASONAL_FACTOR_WATER.mean()


def sample_base_level_elec(n: int) -> np.ndarray:
    """
    สุ่มระดับการใช้ไฟเฉลี่ยต่อบ้าน (หน่วย/เดือน) แบบ log-normal
    เพราะการใช้ไฟจริงเบ้ขวา (ส่วนใหญ่ใช้น้อย-กลาง มีส่วนน้อยใช้เยอะมาก)
    ปรับ mean/sigma ให้ median ~ 350 หน่วย, มีหางยาวไปถึง ~900+
    """
    return np.random.lognormal(mean=np.log(350), sigma=0.45, size=n)


def sample_base_level_water(n: int) -> np.ndarray:
    """หน่วยน้ำเฉลี่ยต่อบ้าน (หน่วย/เดือน) median ~ 15 หน่วย"""
    return np.random.lognormal(mean=np.log(15), sigma=0.35, size=n)


# ---------- สเต็ป 2: trend + noise + step_change + generate เต็มช่วงเวลา ----------

N_MONTHS = 30  # 2.5 ปีย้อนหลังจนถึงปัจจุบัน (ปรับเป็น 24-36 ได้)
START_YEAR = 2024
START_MONTH = 3  # เริ่ม มี.ค. 2024 -> เดือนสุดท้ายจะประมาณ ส.ค. 2026 (ใกล้ปัจจุบัน)

MONTHLY_NOISE_SD = 0.10       # ±10% รบกวนรายเดือน
YEARLY_TREND_SD = 0.03        # แต่ละบ้านมีแนวโน้มข้ามปีต่างกัน (เพิ่ม/ลด) sd 3%/ปี
STEP_CHANGE_PROB = 0.18       # 18% ของบ้านมีเหตุการณ์ทำให้ใช้เพิ่ม/ลดถาวรระหว่างทาง
STEP_CHANGE_SIZE_RANGE = (0.10, 0.30)  # เหตุการณ์เปลี่ยนระดับ 10-30%
AR1_RHO = 0.3                 # noise เดือนติดกันมี correlation เล็กน้อย ไม่ใช่สุ่มอิสระทุกเดือน


def month_index_to_ym(i: int) -> tuple[int, int]:
    """แปลง index (0-based จาก START_YEAR/START_MONTH) เป็น (year, month)"""
    total = (START_MONTH - 1) + i
    year = START_YEAR + total // 12
    month = total % 12 + 1
    return year, month


def generate_series_for_household(base_level: float, seasonal_factor: np.ndarray,
                                    n_months: int, rng: np.random.Generator) -> np.ndarray:
    """
    สร้าง time series หนึ่งบ้าน โดยรวม:
    - seasonal_factor ตามเดือน
    - yearly_trend ต่อเนื่องแบบค่อยเป็นค่อยไป (ไม่ใช่กระโดดเป็นขั้นปี)
    - AR(1) noise เดือนต่อเดือน (มี correlation เล็กน้อยเพื่อความสมจริง)
    - step_change แบบสุ่ม (ไม่ใช่ทุกบ้าน)
    """
    yearly_growth_rate = rng.normal(loc=0.0, scale=YEARLY_TREND_SD)  # ต่อปี
    monthly_growth_rate = (1 + yearly_growth_rate) ** (1 / 12) - 1

    has_step_change = rng.random() < STEP_CHANGE_PROB
    step_month = rng.integers(6, n_months - 3) if has_step_change else None
    step_size = rng.uniform(*STEP_CHANGE_SIZE_RANGE) if has_step_change else 0.0
    step_sign = rng.choice([-1, 1]) if has_step_change else 0

    values = np.empty(n_months)
    noise_prev = 0.0
    level = base_level

    for i in range(n_months):
        year, month = month_index_to_ym(i)
        month_idx = month - 1

        # trend สะสมทีละเดือน
        level *= (1 + monthly_growth_rate)

        # AR(1) noise: ผสม noise เดือนก่อนหน้าเล็กน้อย กันแกว่งสุ่มล้วนๆ
        raw_noise = rng.normal(0, MONTHLY_NOISE_SD)
        noise = AR1_RHO * noise_prev + np.sqrt(1 - AR1_RHO ** 2) * raw_noise
        noise_prev = noise

        # step change: มีผลตั้งแต่ step_month เป็นต้นไป
        step_multiplier = 1.0
        if has_step_change and i >= step_month:
            step_multiplier = 1 + step_sign * step_size

        values[i] = level * seasonal_factor[month_idx] * (1 + noise) * step_multiplier

    return np.clip(values, a_min=0, a_max=None)


def generate_case1_dataset(n_households: int = N_HOUSEHOLDS,
                             n_months: int = N_MONTHS,
                             seed: int = 42):
    rng = np.random.default_rng(seed)
    elec_base_all = sample_base_level_elec(n_households)
    water_base_all = sample_base_level_water(n_households)

    rows = []
    for h in range(n_households):
        elec_series = generate_series_for_household(
            elec_base_all[h], SEASONAL_FACTOR_ELEC, n_months, rng)
        water_series = generate_series_for_household(
            water_base_all[h], SEASONAL_FACTOR_WATER, n_months, rng)

        for i in range(n_months):
            year, month = month_index_to_ym(i)
            rows.append({
                "household_id": f"case1_{h:04d}",
                "case": "bangkok_normal",
                "year": year,
                "month": month,
                "elec_units": round(elec_series[i], 1),
                "water_units": round(water_series[i], 1),
            })
    return rows


if __name__ == "__main__":
    elec_base = sample_base_level_elec(N_HOUSEHOLDS)
    water_base = sample_base_level_water(N_HOUSEHOLDS)

    print("=== ตัวอย่าง base_level ไฟ (หน่วย/เดือน) ===")
    print(f"  min={elec_base.min():.0f}  median={np.median(elec_base):.0f}  "
          f"mean={elec_base.mean():.0f}  max={elec_base.max():.0f}")

    print("\n=== ตัวอย่าง base_level น้ำ (หน่วย/เดือน) ===")
    print(f"  min={water_base.min():.1f}  median={np.median(water_base):.1f}  "
          f"mean={water_base.mean():.1f}  max={water_base.max():.1f}")

    print("\n=== Seasonal factor ไฟ (ม.ค.-ธ.ค.) ===")
    print(np.round(SEASONAL_FACTOR_ELEC, 3))

    print("\n=== Seasonal factor น้ำ (ม.ค.-ธ.ค.) ===")
    print(np.round(SEASONAL_FACTOR_WATER, 3))

    print("\n=== สเต็ป 2: generate เต็ม", N_MONTHS, "เดือน ===")
    rows = generate_case1_dataset()
    import csv
    out_path = "case1_bangkok_normal.csv"
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"เขียนไฟล์ {out_path} แล้ว: {len(rows)} แถว "
          f"({N_HOUSEHOLDS} households x {N_MONTHS} เดือน)")

    # sanity check: ดูตัวอย่าง 1 บ้าน 6 เดือนแรก
    print("\nตัวอย่าง household แรก 6 เดือนแรก:")
    for r in rows[:6]:
        print(f"  {r['year']}-{r['month']:02d}: elec={r['elec_units']}  water={r['water_units']}")

    # sanity check: ค่าเฉลี่ยไฟรวมทุกบ้านแยกตามเดือนปฏิทิน (ไม่แยกปี) ควรเห็นรูปฤดูกาลชัดเจน
    from collections import defaultdict
    by_month = defaultdict(list)
    for r in rows:
        by_month[r["month"]].append(r["elec_units"])
    print("\nค่าเฉลี่ยไฟ รวมทุกบ้าน/ทุกปี แยกตามเดือนปฏิทิน (ควรเห็นพีค เม.ย. ต่ำสุด ธ.ค.):")
    for m in range(1, 13):
        vals = by_month.get(m, [])
        if vals:
            print(f"  เดือน {m:02d}: เฉลี่ย {np.mean(vals):.0f} หน่วย (n={len(vals)})")
