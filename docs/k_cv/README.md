# ผลทดสอบค่า k (EnergyForecaster.priorWeightDays)

หลักฐานของค่า k = 5 ในสูตรคาดการณ์ยอดสิ้นรอบบิล
`อัตราต่อวัน = (ยอดสะสม + อัตรารอบก่อน × k) ÷ (วันที่ผ่านไป + k)`
รันเมื่อ 2026-10-22 (ผลแยกตามวันที่จดรันเพิ่ม 2026-10-23)

- ข้อมูล: RECON-SL smart meter ทุก 6 ชั่วโมง (Algama et al., IEEE DataPort, DOI 10.21227/n1dk-q860, CC BY 4.0)
  เตรียมด้วย `tool/cycle_backtest/prepare_recon_sl.py` (ตัดบ้านโซลาร์) ใช้ได้ราว 2,100 บ้าน 34,000 รอบบิล
- สคริปต์: `tool/backtest_cycle_k_cv.dart` (CV แบ่งตามบ้าน 5 กลุ่ม, bootstrap สุ่มบ้านซ้ำ 1,000 รอบ)
- seed 1-5 · ฤดูกาลไทยจาก `tool/seasonal_curves/seasonal_curves.json`

## ไฟล์

| ไฟล์ | เนื้อหา |
|---|---|
| `k_sensitivity_summary.txt` | สรุปรวม 15 การรัน: MAPE ทุก k, ส่วนต่างเทียบ k = 5 พร้อมช่วง 95%, P(ดีที่สุด) |
| `k_days_summary.txt` | MAPE แยกตามวันที่จด (วันที่ 3-25) ของ k = 0, 3, 4, 5, 21 และการทายเท่ารอบก่อน เฉลี่ย 5 seed |
| `*_days_seed*.csv` | MAPE แยกตามวันที่จดของทุก k และการทายเท่ารอบก่อน แยกตามการรัน |
| `base_seed*.txt/.csv` | ข้อมูลเดิม |
| `bkk_seed*.txt/.csv` | ปรับฤดูกาลไทย กรุงเทพ (`bangkok_normal`) |
| `upc_seed*.txt/.csv` | ปรับฤดูกาลไทย ต่างจังหวัด (`upcountry_normal`) |
| `k_cv_mape_curve.png` | MAPE ตามค่า k ทั้ง 3 ชุด (เฉลี่ย 5 seed) |
| `k_cv_diff_vs_k5.png` | MAPE(k) − MAPE(5) พร้อมช่วง 95% ช่วง k = 2-10 |
| `k_cv_mape_by_day.png` | MAPE แยกตามวันที่จด (ข้อมูลเดิม) ของ k = 0, 5, 21 และการทายเท่ารอบก่อน |
| `k_example_chart.png`, `k_example_table.png` | ตัวอย่างสมมติหนึ่งรอบบิล (ไฟฟ้าและน้ำ) เทียบ k = 0, 3, 5 สำหรับอธิบายสูตร ไม่ใช่หลักฐาน · ข้อมูลใน `k_example_data.txt` จาก `tool/k_example.dart` วาดด้วย `tool/plot_k_example.py` |

## ผลโดยสรุป (เฉลี่ย 5 seed)

| ชุดข้อมูล | k ดีที่สุด | MAPE ที่ k ดีที่สุด | MAPE k = 5 | MAPE k = 0 | MAPE k = 21 |
|---|---|---|---|---|---|
| ข้อมูลเดิม | 5 | 9.02% | 9.02% | 9.92% | 9.41% |
| ฤดูกาลกรุงเทพ | 3 | 9.81% | 9.84% | 10.45% | 10.51% |
| ฤดูกาลต่างจังหวัด | 3 | 9.88% | 9.92% | 10.50% | 10.61% |

MAPE แยกตามวันที่จด (ข้อมูลเดิม): การถ่วงช่วยมากที่สุดช่วงต้นรอบ วันที่ 3 k = 0 16.76% → k = 5 13.68%,
วันที่ 5 14.67% → 12.67%, วันที่ 7 12.76% → 11.54% และแทบไม่ต่างกันตั้งแต่วันที่ 20 ส่วนการทายเท่ารอบก่อน
คลาดราว 14.4% ทุกวัน

ข้อจำกัด: ฤดูกาลไทยถูกคูณซ้อนบนฤดูกาลของศรีลังกา ผลจึงบอกความไวของ k ต่อฤดูกาลที่แรงขึ้น
ไม่ใช่การจำลองบ้านไทยจริง

## รันซ้ำ

```bash
F=<recon_sl_6h.csv>
J=tool/seasonal_curves/seasonal_curves.json
for s in 1 2 3 4 5; do
  dart run tool/backtest_cycle_k_cv.dart --file=$F --seed=$s --csv=docs/k_cv/base_seed$s.csv --days-csv=docs/k_cv/base_days_seed$s.csv > docs/k_cv/base_seed$s.txt
  dart run tool/backtest_cycle_k_cv.dart --file=$F --seed=$s --thai-seasonal=$J --curve=bangkok_normal --csv=docs/k_cv/bkk_seed$s.csv --days-csv=docs/k_cv/bkk_days_seed$s.csv > docs/k_cv/bkk_seed$s.txt
  dart run tool/backtest_cycle_k_cv.dart --file=$F --seed=$s --thai-seasonal=$J --curve=upcountry_normal --csv=docs/k_cv/upc_seed$s.csv --days-csv=docs/k_cv/upc_days_seed$s.csv > docs/k_cv/upc_seed$s.txt
done
python tool/plot_k_cv.py docs/k_cv assets/fonts docs/k_cv   # ต้องมี matplotlib
```
