"""ย่อข้อมูลมิเตอร์อัจฉริยะทุก 6 ชั่วโมงของชุดข้อมูล RECON-SL (ศรีลังกา) ให้เหลือ
เฉพาะที่สคริปต์วัดความแม่นยำยอดสิ้นรอบใช้ (tool/backtest_cycle_dataset.dart)

ชุดข้อมูล: Algama, C. et al. (2026). Residential Electricity Consumption Dataset
for Sri Lanka (RECON-SL). arXiv:2609.28783 · DOI 10.21227/n1dk-q860 · CC BY 4.0

อ่าน consumption_data/smart_meter/6hour_interval/smart_6hour_*.csv แบบไล่ทีละแถว
(ไฟล์รวมราว 1 GB) เก็บเฉพาะ household_ID, วันเวลา และ TOTAL_IMPORT (kWh) ซึ่งเป็น
เลขมิเตอร์สะสม แล้วตัดบ้านที่มีไฟขายคืน (TOTAL_EXPORT > 0 หรือคอลัมน์ EXPORT เป็น
True) เพราะเลข import ของบ้านโซลาร์ไม่ใช่การใช้ไฟทั้งหมด

ผลลัพธ์: CSV คอลัมน์ household,timestamp,kwh เรียงตามบ้านแล้วตามเวลา

วิธีใช้:
  python tool/cycle_backtest/prepare_recon_sl.py --data D:/datasets/recon-sl/data/data \
      --out D:/datasets/recon-sl/derived/recon_sl_6h.csv
"""

import argparse
import csv
import glob
import os
from collections import defaultdict


def normalize_time(t):
    # เวลาบางแถวมีมิลลิวินาทีต่อท้าย (เช่น 01:07:30:056) — ใช้แค่ ชม.:นาที:วินาที
    parts = t.split(':')[:3]
    parts[-1] = parts[-1].split('.')[0]
    return ':'.join(p.zfill(2) for p in parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True, help='โฟลเดอร์ data ของ RECON-SL (ที่มี consumption_data/)')
    ap.add_argument('--out', required=True, help='ไฟล์ CSV ผลลัพธ์')
    args = ap.parse_args()

    pattern = os.path.join(args.data, 'consumption_data', 'smart_meter', '6hour_interval', 'smart_6hour_*.csv')
    files = sorted(glob.glob(pattern))
    if not files:
        raise SystemExit(f'ไม่พบไฟล์ {pattern}')

    readings = defaultdict(list)  # household -> [(timestamp, kwh)]
    exporters = set()
    rows = bad = 0
    for path in files:
        with open(path, newline='', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                rows += 1
                hh = row['household_ID']
                try:
                    kwh = float(row['TOTAL_IMPORT (kWh)'])
                except (ValueError, TypeError):
                    bad += 1
                    continue
                export = row.get('TOTAL_EXPORT (kWh)') or '0'
                try:
                    exported = float(export) > 0
                except ValueError:
                    exported = False
                if exported or row.get('EXPORT') == 'True':
                    exporters.add(hh)
                readings[hh].append((f"{row['DATE']}T{normalize_time(row['TIME'])}", kwh))
        print(f'อ่าน {os.path.basename(path)} แล้ว (รวม {rows:,} แถว)')

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    kept = written = 0
    with open(args.out, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['household', 'timestamp', 'kwh'])
        for hh in sorted(readings):
            if hh in exporters:
                continue
            series = sorted(readings[hh])
            # ตัดค่าที่ทำให้เลขมิเตอร์ถอยหลัง (อ่านผิด/เปลี่ยนมิเตอร์) — เลขสะสมต้องไม่ลดลง
            last = None
            for ts, kwh in series:
                if last is not None and kwh < last:
                    continue
                w.writerow([hh, ts, f'{kwh:.3f}'])
                written += 1
                last = kwh
            kept += 1

    print(f'แถวทั้งหมด {rows:,} (อ่านค่าไม่ได้ {bad:,})')
    print(f'บ้านทั้งหมด {len(readings):,} · ตัดบ้านโซลาร์ {len(exporters):,} · เหลือ {kept:,} บ้าน')
    print(f'เขียน {written:,} แถว -> {args.out}')


if __name__ == '__main__':
    main()
