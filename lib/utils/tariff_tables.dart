// ตารางอัตราค่าไฟฟ้า/ค่าน้ำประปาบ้านอยู่อาศัย และสูตรคิดเงิน — แหล่งเดียวของ
// ตัวเลขอัตราทั้งหมดในโปรเจกต์ เป็น Dart ล้วน (ไม่ import Flutter/Firebase)
// แอป (EnergyCalculator), หน้าอธิบายอัตรา และสคริปต์ใน tool/ จึงใช้ไฟล์นี้ร่วมกันได้
//
// ตรวจกับแหล่งทางการเมื่อ 3 ต.ค. 2569:
//   ไฟฟ้า กฟน. : กกพ. https://www.erc.or.th/th/tariff/1288
//   ไฟฟ้า กฟภ. : https://www.pea.co.th/sites/default/files/documents/tariff/Electricity_Tariff_MAY_2023.pdf
//   น้ำ กปน.   : https://www.mwa.co.th/services/users-should-know/users-service-rate/service-rate/
//   น้ำ กปภ.   : https://www.pwa.co.th/contents/service/table-price (ตารางหมายเลข 3)
// อัตราไฟฟ้าทั้งสองการไฟฟ้าเท่ากัน ต่างกันแค่รหัสประเภท (ดู EnergyCalculator.tariffCode)
// ค่า Ft ไม่อยู่ที่นี่ — ผู้เรียกส่งเข้ามา (ดู EnergyCalculator.getFtInfo)

// ขั้นบันได 1 ขั้น: หน่วยสูงสุดของขั้น (รวม) และราคาต่อหน่วย
typedef TariffTier = ({double upTo, double rate});

class TariffTables {
  TariffTables._();

  static const double vat = 1.07;

  // ==================== ไฟฟ้า ====================

  // ประเภทใช้เกิน 150 หน่วย/เดือน (กฟน. 1.2 / กฟภ. 1.1.2)
  static const List<TariffTier> electricityStandard = [
    (upTo: 150, rate: 3.2484),
    (upTo: 400, rate: 4.2218),
    (upTo: double.infinity, rate: 4.4217),
  ];
  static const double electricityStandardServiceFee = 24.62;

  // ประเภทใช้ไม่เกิน 150 หน่วย/เดือน (กฟน. 1.1 / กฟภ. 1.1.1)
  static const List<TariffTier> electricitySmall = [
    (upTo: 15, rate: 2.3488),
    (upTo: 25, rate: 2.9882),
    (upTo: 35, rate: 3.2405),
    (upTo: 100, rate: 3.6237),
    (upTo: 150, rate: 3.7171),
    (upTo: 400, rate: 4.2218),
    (upTo: double.infinity, rate: 4.4217),
  ];
  static const double electricitySmallServiceFee = 8.19;

  // TOU บ้านอยู่อาศัยแรงดันต่ำ (กฟน. 1.3.2 ต่ำกว่า 12 kV / กฟภ. 1.2.2 ต่ำกว่า
  // 22 kV) — Peak จ.-ศ. 09:00-22:00 น. นอกนั้นรวมวันหยุดเป็น Off-Peak
  // ค่าบริการ 24.62 บาท เท่าประเภท 1.2 (38.22 เป็นของผู้ใช้ไฟประเภทอื่น)
  static const double touPeakRate = 5.7982;
  static const double touOffPeakRate = 2.6369;
  static const double touServiceFee = 24.62;

  // ==================== น้ำประปา ====================

  // กปน. (กรุงเทพฯ) ที่อยู่อาศัย
  static const List<TariffTier> waterMwa = [
    (upTo: 30, rate: 8.50),
    (upTo: 40, rate: 10.03),
    (upTo: 50, rate: 10.35),
    (upTo: 60, rate: 10.68),
    (upTo: 70, rate: 11.00),
    (upTo: 80, rate: 11.33),
    (upTo: 90, rate: 12.50),
    (upTo: 100, rate: 12.82),
    (upTo: 120, rate: 13.15),
    (upTo: 160, rate: 13.47),
    (upTo: 200, rate: 13.80),
    (upTo: double.infinity, rate: 14.45),
  ];
  // ค่าบริการรายเดือนของมาตรวัดน้ำขนาด ½ นิ้ว (บ้านทั่วไป) — มาตรใหญ่กว่านี้
  // ค่าบริการสูงขึ้นตามขนาด แอปไม่ได้ถามขนาดมาตร
  static const double waterMwaServiceFee = 25.00;
  static const double waterMwaRawWaterFee = 0.15; // บาท/หน่วย

  // กปภ. (ต่างจังหวัด) ตารางหมายเลข 3 (สาขาส่วนใหญ่ของประเทศ ยกเว้นบางสาขาใน
  // ตาราง 1, 2 ที่มีอัตราของตัวเอง แอปไม่แยกตามสาขา) — 4 ขั้นแรก (1-50 หน่วย)
  // เป็นอัตราประเภท 1 ที่อยู่อาศัย เดือนที่ใช้เกิน 50 หน่วย หน่วยที่ 51 ขึ้นไป
  // คิดอัตราประเภท 2 (ขั้นที่ 5 เป็นต้นไป) หน่วยที่ 1-50 ยังเป็นอัตราเดิม
  static const List<TariffTier> waterPwa = [
    (upTo: 10, rate: 10.20),
    (upTo: 20, rate: 16.00),
    (upTo: 30, rate: 19.00),
    (upTo: 50, rate: 21.20),
    (upTo: 80, rate: 21.60),
    (upTo: 100, rate: 21.65),
    (upTo: 300, rate: 21.70),
    (upTo: 1000, rate: 21.75),
    (upTo: 2000, rate: 21.80),
    (upTo: 3000, rate: 21.85),
    (upTo: double.infinity, rate: 21.90),
  ];
  static const double waterPwaServiceFee = 30.00; // มาตร ½ นิ้ว

  // ==================== สูตร ====================

  // ค่าพลังงาน/ค่าน้ำตามขั้นบันได (ยังไม่รวมค่าบริการ/VAT)
  static double tiered(double units, List<TariffTier> tiers) {
    double cost = 0;
    double lower = 0;
    for (final t in tiers) {
      if (units <= lower) break;
      cost += ((units < t.upTo ? units : t.upTo) - lower) * t.rate;
      lower = t.upTo;
    }
    return cost;
  }

  static double round2(double v) => double.parse(v.toStringAsFixed(2));

  // ทุกสูตรด้านล่าง: ใช้ 0 หน่วยยังเสียค่าบริการรายเดือน (+ VAT) เหมือนใบแจ้งหนี้จริง

  // ค่าไฟมิเตอร์ปกติ [small] = ประเภทใช้ไม่เกิน 150 หน่วย, [ftRate] บาท/หน่วย
  static double electricity(double units, {required double ftRate, bool small = false}) {
    if (units < 0) units = 0;
    final energy = tiered(units, small ? electricitySmall : electricityStandard);
    final fee = small ? electricitySmallServiceFee : electricityStandardServiceFee;
    return round2((energy + fee + units * ftRate) * vat);
  }

  static double electricityTou(double peakUnits, double offPeakUnits, {required double ftRate}) {
    if (peakUnits < 0) peakUnits = 0;
    if (offPeakUnits < 0) offPeakUnits = 0;
    final energy = peakUnits * touPeakRate + offPeakUnits * touOffPeakRate;
    return round2((energy + touServiceFee + (peakUnits + offPeakUnits) * ftRate) * vat);
  }

  // ที่อยู่อาศัยไม่มีค่าน้ำขั้นต่ำ — กปน. ยกเลิกตั้งแต่งวด 1 เม.ย. 2558, กปภ.
  // กำหนดขั้นต่ำเฉพาะประเภท 2 และ 3
  static double waterMwaCost(double units) {
    if (units < 0) units = 0;
    final cost = tiered(units, waterMwa) + waterMwaServiceFee + units * waterMwaRawWaterFee;
    return round2(cost * vat);
  }

  static double waterPwaCost(double units) {
    if (units < 0) units = 0;
    return round2((tiered(units, waterPwa) + waterPwaServiceFee) * vat);
  }

  // หน่วยที่ใช้ = เลขใหม่ - เลขเดิม ปัดทศนิยม 2 ตำแหน่ง
  // คืน 0 เมื่อเลขใหม่ไม่มากกว่าเลขเดิม (ไม่มีทางได้ค่าติดลบ)
  static double unitsUsed(double current, double previous) {
    if (current <= previous) return 0;
    return round2(current - previous);
  }
}
