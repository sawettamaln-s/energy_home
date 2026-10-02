"""
สร้างตัวคูณฤดูกาล (seasonal index) รายเดือนจากสถิติการใช้ไฟฟ้า/น้ำประปาจริง
ของภาคที่อยู่อาศัย แล้วเขียนออกเป็น lib/utils/seasonal_curves.dart

แหล่งข้อมูล (ข้อมูลเปิดของหน่วยงานรัฐ):
  - ไฟฟ้า กทม.+ปริมณฑล : สนพ. (EPPO) "การใช้ไฟฟ้าในพื้นที่ กฟน. ตามสาขา"
    https://catalog.eppo.go.th/dataset/dataset_11_35  (Sector = Residential, GWh)
  - ไฟฟ้า ภูมิภาค       : สนพ. (EPPO) "การใช้ไฟฟ้าในพื้นที่ กฟภ. ตามสาขา"
    https://gdcatalog.go.th/en/dataset/gdpublish-dataset-11-361 (Residential, GWh)
  - น้ำ กทม.+ปริมณฑล   : กปน. (MWA) "สถิติการใช้น้ำประปา" แยกตามกลุ่มผู้ใช้น้ำ
    https://gdcatalog.go.th/dataset/gdpublish-cus-consumption
    (CLASS_GROUP_CODE = 1 ที่อยู่อาศัย, ลบ.ม.)
  - น้ำ ภูมิภาค          : กปภ. ไม่เปิดเผยข้อมูลรายเดือนแยกประเภทผู้ใช้ จึงใช้
    รูปแบบของ กปน. แทน (ข้อจำกัดที่ต้องระบุในรายงาน)
  ข้อมูลทั้งหมดเป็นยอด "ออกบิล" ของเดือนนั้น ตรงกับวิธีที่แอปตั้งชื่อบิล
  ด้วยเดือนของใบแจ้งหนี้

วิธีคำนวณ (classical multiplicative decomposition):
  1) หาค่าเฉลี่ยเคลื่อนที่แบบกึ่งกลาง 2x12 เดือน เพื่อตัดแนวโน้มระยะยาว
     (จำนวนผู้ใช้ที่เพิ่มขึ้นทุกปี) ออก
  2) อัตราส่วน = ค่าจริง / ค่าเฉลี่ยเคลื่อนที่ ของแต่ละเดือน
  3) เฉลี่ยอัตราส่วนของเดือนเดียวกันข้ามปีในช่วงที่เลือก (ตัดปี 2020-2021 ที่
     พฤติกรรมเปลี่ยนผิดปกติจากล็อกดาวน์โควิด) แล้วปรับให้ค่าเฉลี่ย 12 เดือน = 1.0
  มิเตอร์ TOU ใช้รูปแบบเดียวกับมิเตอร์ปกติของภาคเดียวกัน เพราะสถิติรวมไม่ได้
  แยกประเภทมิเตอร์

วิธีใช้:
  python tool/seasonal_curves/build_seasonal_curves.py --fetch   # ดาวน์โหลดใหม่ + สร้าง
  python tool/seasonal_curves/build_seasonal_curves.py           # สร้างจาก data/*.csv
"""

import argparse
import csv
import io
import json
import os
import sys
import urllib.request
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, 'data')
PROJECT_ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
DART_OUT = os.path.join(PROJECT_ROOT, 'lib', 'utils', 'seasonal_curves.dart')
JSON_OUT = os.path.join(HERE, 'seasonal_curves.json')

EPPO_MEA_URL = ('https://catalog.eppo.go.th/dataset/fbc8e2ff-2b0e-416c-b6d6-b90d134eb05e/'
                'resource/6f003d40-6290-4ca5-9ad1-bbad56f53baa/download/dataset_11_35.csv')
EPPO_PEA_URL = ('https://catalog.eppo.go.th/dataset/f5f0bccc-2fad-410f-ac1f-d52664746855/'
                'resource/73983b68-9667-4b2a-9948-d76f2146b2c7/download/dataset_11_36.csv')
MWA_BASE = 'https://opendata.mwa.co.th/dataset/ab24a2a3-413d-4e7c-8aa5-d519b535cdfb/resource/'
MWA_YEAR_FILES = {  # ปี พ.ศ. -> path ของไฟล์รายปี
    2557: 'c74aa03f-bd28-449c-8530-a2db0f2db044/download/2557.csv',
    2558: '1d26bb4d-5cef-43af-b077-a3009f505f14/download/2558.csv',
    2559: '7a45e89d-7e71-4446-b80c-044ae6af1b35/download/2559.csv',
    2560: '363134da-4b37-4e48-8eea-c20a2c4692ed/download/2560.csv',
    2561: '2eb4b36e-85d6-4609-9060-e22ea364c898/download/2561.csv',
    2562: '6432dfb1-09d5-4f34-b0b3-c5ed4dae80df/download/2562.csv',
    2563: '48142d31-bbb6-48a6-9576-e2d8137bfbf0/download/2563.csv',
    2564: '5f67696b-d54b-421b-8d71-344e77316fb7/download/2564.csv',
    2565: 'daaf73d0-a8dd-42af-abc0-e4399a7371e1/download/2565.csv',
    2566: 'b6b01163-0db3-47d6-ba15-ed389c35091d/download/25661.csv',
    2567: 'a178a18a-d4d4-45e1-baa3-a052adb12861/download/con_by_district_2567.csv',
    2568: '645cbbfe-1c02-4c76-9439-8e51d266908a/download/con_by_district_2568.csv',
}

MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
          'August', 'September', 'October', 'November', 'December']

# ปีที่ใช้คำนวณ (ค.ศ.) — 10 ปีล่าสุดที่ครบ 12 เดือน ไม่รวมช่วงโควิด
CURVE_YEARS = [y for y in range(2016, 2026) if y not in (2020, 2021)]

# ชุดข้อมูลที่ใช้สร้างแต่ละ curve (ไฟล์ใน data/)
SERIES_FILES = {
    'elec_bangkok': 'elec_mea_residential.csv',
    'elec_upcountry': 'elec_pea_residential.csv',
    'water_bangkok': 'water_mwa_residential.csv',
}


def _download(url):
    # เซิร์ฟเวอร์บางแห่งปฏิเสธคำขอที่ไม่มี User-Agent (HTTP 403)
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read().decode('utf-8-sig', errors='replace')


def _write_series(name, rows, unit):
    os.makedirs(DATA_DIR, exist_ok=True)
    path = os.path.join(DATA_DIR, name)
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['year', 'month', 'value', 'unit'])
        for (y, m), v in sorted(rows.items()):
            w.writerow([y, m, round(v, 3), unit])
    print(f'  เขียน {path} ({len(rows)} เดือน)')


def fetch():
    """ดาวน์โหลดข้อมูลต้นทาง แล้วสรุปเป็นยอดที่อยู่อาศัยรายเดือนใน data/*.csv"""
    for name, url in (('elec_mea_residential.csv', EPPO_MEA_URL),
                      ('elec_pea_residential.csv', EPPO_PEA_URL)):
        print(f'ดาวน์โหลด {url}')
        rows = {}
        for r in csv.DictReader(io.StringIO(_download(url))):
            if r['Sector'].strip() != 'Residential':
                continue
            rows[(int(r['Year']), MONTHS.index(r['Month'].strip()) + 1)] = float(r['Quantity'])
        _write_series(name, rows, 'GWh')

    water = defaultdict(float)
    for be_year, path in MWA_YEAR_FILES.items():
        print(f'ดาวน์โหลด กปน. ปี {be_year}')
        reader = csv.reader(io.StringIO(_download(MWA_BASE + path)))
        header = [h.strip().upper() for h in next(reader)]
        i_month = header.index('PERIOD_MONTH') if 'PERIOD_MONTH' in header else header.index('DATA_MM')
        i_class = header.index('CLASS_GROUP_CODE')
        i_value = header.index('CONSUMPTION')
        for row in reader:
            if len(row) <= i_value or row[i_class].strip() != '1':
                continue
            water[(be_year - 543, int(float(row[i_month])))] += float(row[i_value])
    _write_series('water_mwa_residential.csv', water, 'm3')


def read_series(name):
    rows = {}
    with open(os.path.join(DATA_DIR, name), encoding='utf-8') as f:
        for r in csv.DictReader(f):
            rows[(int(r['year']), int(r['month']))] = float(r['value'])
    return rows


def seasonal_index(series, years):
    """ตัวคูณฤดูกาล 12 ค่า (ม.ค.-ธ.ค.) เฉลี่ย = 1.0 จากปีที่ระบุ"""
    keys = sorted(series)
    values = [series[k] for k in keys]
    ratios = defaultdict(list)
    for i in range(6, len(values) - 6):
        # ค่าเฉลี่ยเคลื่อนที่กึ่งกลาง 2x12: ครึ่งน้ำหนักที่ปลายทั้งสองข้าง
        window = values[i - 6:i + 7]
        cma = (0.5 * window[0] + sum(window[1:12]) + 0.5 * window[12]) / 12
        year, month = keys[i]
        if year in years:
            ratios[month].append(values[i] / cma)
    missing = [m for m in range(1, 13) if not ratios[m]]
    if missing:
        raise ValueError(f'ข้อมูลไม่พอสำหรับเดือน {missing}')
    raw = [sum(ratios[m]) / len(ratios[m]) for m in range(1, 13)]
    mean = sum(raw) / 12
    return [v / mean for v in raw]


def build_curves(years=CURVE_YEARS):
    series = {k: read_series(f) for k, f in SERIES_FILES.items()}
    elec_bkk = seasonal_index(series['elec_bangkok'], years)
    elec_up = seasonal_index(series['elec_upcountry'], years)
    water_bkk = seasonal_index(series['water_bangkok'], years)
    return {
        'elec': {
            'bangkok_normal': elec_bkk, 'bangkok_tou': elec_bkk,
            'upcountry_normal': elec_up, 'upcountry_tou': elec_up,
        },
        'water': {
            'bangkok_normal': water_bkk, 'bangkok_tou': water_bkk,
            # กปภ. ไม่มีข้อมูลรายเดือนแยกที่อยู่อาศัย — ใช้รูปแบบ กปน. แทน
            'upcountry_normal': water_bkk, 'upcountry_tou': water_bkk,
        },
    }


def _dart_list(values):
    return '[' + ', '.join(f'{v:.4f}' for v in values) + ']'


def write_outputs(curves):
    with open(JSON_OUT, 'w', encoding='utf-8') as f:
        json.dump({'years': CURVE_YEARS, 'curves': curves}, f, indent=2)

    years_label = ', '.join(str(y) for y in CURVE_YEARS)
    lines = [
        '// GENERATED FILE — อย่าแก้ตรงนี้ตรงๆ',
        '// สร้างโดย tool/seasonal_curves/build_seasonal_curves.py',
        '// จากสถิติการใช้ไฟฟ้า/น้ำประปาจริงของภาคที่อยู่อาศัยรายเดือน:',
        '//   ไฟฟ้า: สนพ. (EPPO) การใช้ไฟฟ้าในพื้นที่ กฟน./กฟภ. ตามสาขา (Residential)',
        '//   น้ำ  : กปน. (MWA) สถิติการใช้น้ำประปา กลุ่มที่อยู่อาศัย',
        f'// ปีที่ใช้ (ค.ศ.): {years_label}',
        '',
        '/// ตัวคูณตามฤดูกาลของแต่ละเคส (ม.ค.=index 0 ... ธ.ค.=index 11)',
        '/// ค่าเฉลี่ยรวม 12 เดือน = 1.0 เสมอ — มากกว่า 1 = เดือนที่ใช้มากกว่าปกติ',
        '/// มิเตอร์ TOU ใช้รูปแบบเดียวกับมิเตอร์ปกติของภาคเดียวกัน (สถิติไม่ได้แยก)',
        '/// น้ำภูมิภาคใช้รูปแบบของ กปน. (กปภ. ไม่เปิดเผยข้อมูลรายเดือนแยกที่อยู่อาศัย)',
        'class SeasonalCurves {',
    ]
    for kind in ('elec', 'water'):
        lines.append(f'  static const Map<String, List<double>> {kind} = {{')
        for key, values in curves[kind].items():
            lines.append(f"    '{key}': {_dart_list(values)},")
        lines.append('  };')
        lines.append('')
    lines += [
        '  /// รวม area+meterType เป็น case key ให้ตรงกับที่ใช้ในนี้',
        '  static String caseKeyFor({required String area, required String meterType}) {',
        "    final region = area == 'bangkok' ? 'bangkok' : 'upcountry';",
        "    final meter = meterType == 'tou' ? 'tou' : 'normal';",
        "    return '${region}_$meter';",
        '  }',
        '}',
        '',
    ]
    with open(DART_OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))
    print(f'เขียน {DART_OUT}')


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--fetch', action='store_true',
                        help='ดาวน์โหลดข้อมูลต้นทางใหม่ก่อนสร้าง')
    args = parser.parse_args()
    if args.fetch:
        fetch()
    curves = build_curves()
    month_names = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
                   'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.']
    for kind, key in (('elec', 'bangkok_normal'), ('elec', 'upcountry_normal'),
                      ('water', 'bangkok_normal')):
        vals = curves[kind][key]
        print(f'{kind:5} {key:17}', ' '.join(f'{n}:{v:.3f}' for n, v in zip(month_names, vals)))
    write_outputs(curves)


if __name__ == '__main__':
    main()
