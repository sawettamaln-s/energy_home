"""
สเต็ป 7: แปลง seasonal_curves.json -> ไฟล์ Dart const

รันหลังจากรัน blend_seasonal_curves.py แล้วเท่านั้น (ต้องมี seasonal_curves.json
อยู่ในโฟลเดอร์เดียวกันก่อน)

ผลลัพธ์: เขียนไฟล์ lib/utils/seasonal_curves.dart ให้อัตโนมัติ
(เขียนทับของเดิมทุกครั้งที่รัน เผื่อรันซ้ำตอนมีข้อมูลจริงเพิ่ม)
"""

import json
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
JSON_PATH = os.path.join(SCRIPT_DIR, "seasonal_curves.json")

# lib/utils/ อยู่ 3 ระดับขึ้นไปจาก tool/forecast_synth/
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUTPUT_PATH = os.path.join(PROJECT_ROOT, "lib", "utils", "seasonal_curves.dart")


def dart_list(values):
    return "[" + ", ".join(f"{v:.4f}" for v in values) + "]"


def main():
    if not os.path.exists(JSON_PATH):
        print(f"ไม่พบ {JSON_PATH} — ต้องรัน blend_seasonal_curves.py ก่อน")
        return

    with open(JSON_PATH, encoding="utf-8") as f:
        data = json.load(f)

    elec_entries = []
    water_entries = []
    for case in data:
        elec_entries.append(f"    '{case['case']}': {dart_list(case['elec'])},")
        water_entries.append(f"    '{case['case']}': {dart_list(case['water'])},")

    dart_code = f"""// GENERATED FILE — อย่าแก้ตรงนี้ตรงๆ
// สร้างจาก tool/forecast_synth/seasonal_curves.json
// โดย tool/forecast_synth/export_curves_to_dart.py
// รันสคริปต์นั้นใหม่ทุกครั้งที่มีข้อมูลจริงเพิ่ม เพื่ออัปเดตไฟล์นี้

/// ตัวคูณตามฤดูกาลของแต่ละเคส (ม.ค.=index 0 ... ธ.ค.=index 11)
/// ค่าเฉลี่ยรวม 12 เดือน = 1.0 เสมอ
/// ผสมจากข้อมูลสมมติ (synthetic) + ข้อมูลจริงเท่าที่มี ณ ตอน export
class SeasonalCurves {{
  static const Map<String, List<double>> elec = {{
{chr(10).join(elec_entries)}
  }};

  static const Map<String, List<double>> water = {{
{chr(10).join(water_entries)}
  }};

  /// รวม area+meterType เป็น case key ให้ตรงกับที่ใช้ในนี้
  static String caseKeyFor({{required String area, required String meterType}}) {{
    final region = area == 'bangkok' ? 'bangkok' : 'upcountry';
    final meter = meterType == 'tou' ? 'tou' : 'normal';
    return '${{region}}_$meter';
  }}
}}
"""

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write(dart_code)

    print(f"เขียน {OUTPUT_PATH} แล้ว ({len(data)} เคส)")


if __name__ == "__main__":
    main()