"""
สเต็ป 5: ผสม synthetic (prior) + ข้อมูลจริง (real) เป็น seasonal curve สุดท้าย

อ่านไฟล์คู่ต่อ 1 เคส:
  synthetic: case1_bangkok_normal.csv ฯลฯ (มีอยู่แล้วครบ 4 เคส)
  real:      real_bangkok_normal.csv ฯลฯ (มีเท่าที่ export มาได้จริง อาจไม่ครบ 4 เคส)

ถ้าไฟล์ real ของเคสไหนยังไม่มี (ยังไม่เคย export) -> ใช้ synthetic ล้วนๆ
ไปก่อนโดยอัตโนมัติ ไม่ error ไม่ต้องแก้โค้ด

หลักการ:
1. Normalize ข้อมูลแต่ละ household ให้เป็นสัดส่วนจากค่าเฉลี่ยของ household นั้นเอง
   (กัน scale บ้านใหญ่/เล็กมากวนรูปฤดูกาล)
2. เฉลี่ย normalized value ต่อเดือนปฏิทิน ข้าม households -> ได้ curve
3. ผสม synthetic curve (prior) กับ real curve ด้วยสูตร:
     final[month] = (n_real[month]*real[month] + k*prior[month]) / (n_real[month]+k)
   เดือนไหนไม่มีข้อมูลจริงเลย (n_real=0) -> final = prior พอดี (fallback อัตโนมัติ)
4. Renormalize final curve ให้ค่าเฉลี่ยทั้งปี = 1.0 อีกครั้ง

ผลลัพธ์: seasonal_curves.json (4 เคส x elec/water x 12 เดือน)
"""

import csv
import json
import os
from collections import defaultdict

# ยิ่ง k สูง ยิ่งเชื่อ synthetic (prior) มากกว่าข้อมูลจริง จนกว่าจะมีข้อมูลจริงเยอะพอ
# n_real ต้องเยอะกว่า k หลายเท่าถึงจะเริ่มเอียงไปทางข้อมูลจริงเป็นหลัก
K_TRUST_PRIOR = 75

CASES = [
    {
        "case_id": "bangkok_normal",
        "synthetic_file": "case1_bangkok_normal.csv",
        "real_file": "real_bangkok_normal.csv",
        "is_tou": False,
    },
    {
        "case_id": "bangkok_tou",
        "synthetic_file": "case2_bangkok_tou.csv",
        "real_file": "real_bangkok_tou.csv",
        "is_tou": True,
    },
    {
        "case_id": "upcountry_normal",
        "synthetic_file": "case3_upcountry_normal.csv",
        "real_file": "real_upcountry_normal.csv",
        "is_tou": False,
    },
    {
        "case_id": "upcountry_tou",
        "synthetic_file": "case4_upcountry_tou.csv",
        "real_file": "real_upcountry_tou.csv",
        "is_tou": True,
    },
]


# หา path ให้ยึดตามตำแหน่งของไฟล์สคริปต์นี้เอง ไม่ใช่ยึดตาม
# โฟลเดอร์ที่ตอนรันคำสั่งอยู่ (ทำให้รันจาก root โปรเจกต์ก็หาไฟล์เจอ)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def read_csv_rows(filename):
    path = os.path.join(SCRIPT_DIR, filename)
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = []
        for r in reader:
            r["month"] = int(r["month"])
            r["year"] = int(r["year"])
            if "elec_units" in r:
                r["elec_units"] = float(r["elec_units"])
            if "elec_units_onpeak" in r:
                r["elec_units_onpeak"] = float(r["elec_units_onpeak"])
                r["elec_units_offpeak"] = float(r["elec_units_offpeak"])
                r["elec_units"] = r["elec_units_onpeak"] + r["elec_units_offpeak"]
            r["water_units"] = float(r["water_units"])
            rows.append(r)
        return rows


def normalized_monthly_curve(rows, value_key):
    """
    Normalize ต่อ household (หารด้วยค่าเฉลี่ยของ household นั้นเอง) แล้วเฉลี่ยรายเดือน
    คืนค่า (curve: {month: avg_or_None}, counts: {month: n_observations})
    """
    household_values = defaultdict(list)
    for r in rows:
        household_values[r["household_id"]].append((r["month"], r[value_key]))

    monthly_normalized = defaultdict(list)
    for _, entries in household_values.items():
        vals = [v for _, v in entries]
        mean = sum(vals) / len(vals) if vals else 0
        if mean <= 0:
            continue
        for month, v in entries:
            monthly_normalized[month].append(v / mean)

    curve, counts = {}, {}
    for m in range(1, 13):
        vals = monthly_normalized.get(m, [])
        counts[m] = len(vals)
        curve[m] = sum(vals) / len(vals) if vals else None
    return curve, counts


def blend(prior_curve, real_curve, real_counts, k=K_TRUST_PRIOR):
    final = {}
    for m in range(1, 13):
        p = prior_curve.get(m) if prior_curve.get(m) is not None else 1.0
        n = real_counts.get(m, 0)
        r = real_curve.get(m)
        if n > 0 and r is not None:
            final[m] = (n * r + k * p) / (n + k)
        else:
            final[m] = p
    # renormalize ให้เฉลี่ยทั้งปี = 1.0 พอดี
    mean = sum(final.values()) / 12
    if mean > 0:
        final = {m: v / mean for m, v in final.items()}
    return final


def process_case(case_info):
    synthetic_rows = read_csv_rows(case_info["synthetic_file"])
    real_rows = read_csv_rows(case_info["real_file"])

    result = {"case": case_info["case_id"], "n_real_rows": len(real_rows)}

    for value_key, out_key in [("elec_units", "elec"), ("water_units", "water")]:
        prior_curve, _ = normalized_monthly_curve(synthetic_rows, value_key)
        real_curve, real_counts = normalized_monthly_curve(real_rows, value_key)
        final_curve = blend(prior_curve, real_curve, real_counts)
        result[out_key] = [round(final_curve[m], 4) for m in range(1, 13)]
        result[f"{out_key}_n_real_by_month"] = [real_counts.get(m, 0) for m in range(1, 13)]

    return result


if __name__ == "__main__":
    all_results = []
    for case_info in CASES:
        r = process_case(case_info)
        all_results.append(r)

        has_real = r["n_real_rows"] > 0
        print(f"\n=== เคส {r['case']} "
              f"({'มีข้อมูลจริง ' + str(r['n_real_rows']) + ' แถว' if has_real else 'ยังไม่มีข้อมูลจริง — ใช้ synthetic ล้วนๆ'}) ===")
        print("  elec curve (ม.ค.-ธ.ค.):", r["elec"])
        print("  water curve (ม.ค.-ธ.ค.):", r["water"])
        if has_real:
            print("  จำนวนข้อมูลจริงต่อเดือน (elec):", r["elec_n_real_by_month"])

    out_path = os.path.join(SCRIPT_DIR, "seasonal_curves.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(all_results, f, ensure_ascii=False, indent=2)
    print(f"\nเขียนผลลัพธ์รวมทั้งหมดลง {out_path} แล้ว")