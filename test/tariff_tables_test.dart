// เทสตารางอัตรา/สูตรคิดเงิน (lib/utils/tariff_tables.dart) ด้วยตัวเลขที่คิดมือ
// ตามประกาศอัตรา — แอป, หน้าอธิบายอัตรา และสคริปต์ใน tool/ ใช้ไฟล์นี้ร่วมกัน
import 'package:energy_home/utils/tariff_tables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ไฟฟ้าใช้เกิน 150 หน่วย: 200 หน่วย Ft 16.23 สตางค์', () {
    // 150 × 3.2484 + 50 × 4.2218 = 698.35, + ค่าบริการ 24.62 + Ft 200 × 0.1623
    // = 755.43, × 1.07 = 808.31
    expect(TariffTables.electricity(200, ftRate: 0.1623), 808.31);
  });

  test('ไฟฟ้าใช้ไม่เกิน 150 หน่วย: 50 หน่วย ไม่มี Ft', () {
    // 15 × 2.3488 + 10 × 2.9882 + 10 × 3.2405 + 15 × 3.6237 = 151.8745
    // + ค่าบริการ 8.19 = 160.0645, × 1.07 = 171.27
    expect(TariffTables.electricity(50, ftRate: 0, small: true), 171.27);
  });

  test('TOU: On-Peak 100 + Off-Peak 300 หน่วย ไม่มี Ft', () {
    // 100 × 5.7982 + 300 × 2.6369 = 1,370.89, + 24.62 = 1,395.51, × 1.07 = 1,493.20
    expect(TariffTables.electricityTou(100, 300, ftRate: 0), 1493.2);
  });

  test('น้ำ กปน. 35 หน่วย', () {
    // 30 × 8.50 + 5 × 10.03 = 305.15, + ค่าบริการ 25 + ค่าน้ำดิบ 35 × 0.15
    // = 335.40, × 1.07 = 358.88
    expect(TariffTables.waterMwaCost(35), 358.88);
  });

  test('น้ำ กปภ. 60 หน่วย: หน่วยที่ 51 ขึ้นไปคิดอัตราขั้นถัดไป', () {
    // 10 × 10.20 + 10 × 16 + 10 × 19 + 20 × 21.20 = 876, + 10 × 21.60 = 1,092
    // + ค่าบริการ 30 = 1,122, × 1.07 = 1,200.54
    expect(TariffTables.waterPwaCost(60), 1200.54);
  });

  test('ตารางขั้นบันไดเรียงจากน้อยไปมาก และขั้นสุดท้ายไม่มีเพดาน', () {
    for (final tiers in [
      TariffTables.electricityStandard,
      TariffTables.electricitySmall,
      TariffTables.waterMwa,
      TariffTables.waterPwa,
    ]) {
      for (var i = 1; i < tiers.length; i++) {
        expect(tiers[i].upTo, greaterThan(tiers[i - 1].upTo));
      }
      expect(tiers.last.upTo, double.infinity);
    }
  });
}
