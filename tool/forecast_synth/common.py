"""
ฟังก์ชันร่วมที่ใช้ทั้ง 4 เคส
"""
import csv
import numpy as np

MONTHLY_NOISE_SD = 0.10
YEARLY_TREND_SD = 0.03
STEP_CHANGE_PROB = 0.18
STEP_CHANGE_SIZE_RANGE = (0.10, 0.30)
AR1_RHO = 0.3


def month_index_to_ym(start_year: int, start_month: int, i: int) -> tuple[int, int]:
    total = (start_month - 1) + i
    year = start_year + total // 12
    month = total % 12 + 1
    return year, month


def cooling_degree_index(mean_temp_c: np.ndarray, threshold_c: float = 26.0) -> np.ndarray:
    """แปลงอุณหภูมิเฉลี่ยรายเดือนเป็น cooling-degree index normalize เฉลี่ย = 1.0"""
    degree = np.clip(mean_temp_c - threshold_c, 0, None)
    return degree / degree.mean()


def seasonal_factor_from_degree_index(degree_index: np.ndarray, base_fraction: float) -> np.ndarray:
    variable_fraction = 1.0 - base_fraction
    factor = base_fraction + variable_fraction * degree_index
    return factor / factor.mean()


def generate_series_for_household(base_level: float, seasonal_factor: np.ndarray,
                                    n_months: int, start_year: int, start_month: int,
                                    rng: np.random.Generator) -> np.ndarray:
    yearly_growth_rate = rng.normal(loc=0.0, scale=YEARLY_TREND_SD)
    monthly_growth_rate = (1 + yearly_growth_rate) ** (1 / 12) - 1

    has_step_change = rng.random() < STEP_CHANGE_PROB
    step_month = rng.integers(6, max(7, n_months - 3)) if has_step_change else None
    step_size = rng.uniform(*STEP_CHANGE_SIZE_RANGE) if has_step_change else 0.0
    step_sign = rng.choice([-1, 1]) if has_step_change else 0

    values = np.empty(n_months)
    noise_prev = 0.0
    level = base_level

    for i in range(n_months):
        _, month = month_index_to_ym(start_year, start_month, i)
        month_idx = month - 1

        level *= (1 + monthly_growth_rate)

        raw_noise = rng.normal(0, MONTHLY_NOISE_SD)
        noise = AR1_RHO * noise_prev + np.sqrt(1 - AR1_RHO ** 2) * raw_noise
        noise_prev = noise

        step_multiplier = 1.0
        if has_step_change and i >= step_month:
            step_multiplier = 1 + step_sign * step_size

        values[i] = level * seasonal_factor[month_idx] * (1 + noise) * step_multiplier

    return np.clip(values, a_min=0, a_max=None)


def write_csv(rows: list[dict], path: str):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


def print_monthly_summary(rows: list[dict], value_key: str, label: str):
    from collections import defaultdict
    by_month = defaultdict(list)
    for r in rows:
        by_month[r["month"]].append(r[value_key])
    print(f"\nค่าเฉลี่ย {label} รวมทุกบ้าน/ทุกปี แยกตามเดือนปฏิทิน:")
    for m in range(1, 13):
        vals = by_month.get(m, [])
        if vals:
            print(f"  เดือน {m:02d}: เฉลี่ย {np.mean(vals):.0f} (n={len(vals)})")
