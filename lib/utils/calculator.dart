import 'package:cloud_firestore/cloud_firestore.dart';

// อัตราค่าไฟฟ้า/ค่าน้ำประปาบ้านอยู่อาศัย — ตรวจกับแหล่งทางการเมื่อ 3 ต.ค. 2569:
//   ไฟฟ้า กฟน. : กกพ. https://www.erc.or.th/th/tariff/1288
//   ไฟฟ้า กฟภ. : https://www.pea.co.th/sites/default/files/documents/tariff/Electricity_Tariff_MAY_2023.pdf
//   ค่า Ft     : กกพ. https://www.erc.or.th/th/news-release/3458 (งวด ก.ย.-ธ.ค. 2569 = 16.23 สตางค์)
//   น้ำ กปน.   : https://www.mwa.co.th/services/users-should-know/users-service-rate/service-rate/
//   น้ำ กปภ.   : https://www.pwa.co.th/contents/service/table-price (ตารางหมายเลข 3)
// อัตราไฟฟ้าทั้งสองการไฟฟ้าเท่ากัน ต่างกันแค่รหัสประเภท (ดู tariffCode)

// ค่า Ft ที่แอปใช้ และวันที่เริ่มใช้งวดนั้น (null = ผู้ดูแลยังไม่ได้ระบุ)
typedef FtInfo = ({double rate, DateTime? effectiveFrom});

class EnergyCalculator {
  // ค่า Ft งวดล่าสุดที่ผู้ดูแลตั้งไว้ใน app_config/electricity_rates (แก้ผ่าน
  // Firebase Console ทุกครั้งที่ กกพ. ประกาศงวดใหม่ ทุก 4 เดือน: ม.ค./พ.ค./ก.ย.)
  // อ่านไม่ได้ (ออฟไลน์/ยังไม่มีเอกสาร) ใช้ค่าของงวด ก.ย.-ธ.ค. 2569 แทน
  static const double defaultFtRate = 0.1623;

  static Future<double> getFtRate() async => (await getFtInfo()).rate;

  // ft_rate = บาท/หน่วย, ft_effective_from = วันเริ่มงวด (ISO เช่น 2026-09-01)
  static Future<FtInfo> getFtInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('electricity_rates')
          .get();
      final data = doc.data();
      return (
        rate: ((data?['ft_rate'] ?? defaultFtRate) as num).toDouble(),
        effectiveFrom: DateTime.tryParse('${data?['ft_effective_from'] ?? ''}'),
      );
    } catch (e) {
      return (rate: defaultFtRate, effectiveFrom: null);
    }
  }

  // ค่า Ft ประกาศใหม่ทุก 4 เดือน — งวดที่ใช้อยู่เริ่มก่อน [now] เกิน 4 เดือน
  // แปลว่าผู้ดูแลยังไม่ได้อัปเดตงวดใหม่ (ไม่รู้วันเริ่มงวด = ตัดสินไม่ได้ คืน false)
  static bool isFtOutdated(DateTime? effectiveFrom, DateTime now) {
    if (effectiveFrom == null) return false;
    final nextPeriod =
        DateTime(effectiveFrom.year, effectiveFrom.month + 4, effectiveFrom.day);
    return !now.isBefore(nextPeriod);
  }

  // รหัสประเภทอัตราตามที่พิมพ์บนใบแจ้งหนี้ — อัตราเท่ากัน แต่ กฟน. กับ กฟภ.
  // ตั้งชื่อต่างกัน: กฟน. 1.1 / 1.2 (TOU = 1.3.2), กฟภ. 1.1.1 / 1.1.2 (TOU = 1.2.2)
  static String tariffCode(String tariff, String area) {
    final isBangkok = area == 'bangkok';
    if (tariff == tariffSmall) return isBangkok ? '1.1' : '1.1.1';
    return isBangkok ? '1.2' : '1.1.2';
  }

  static String touCode(String area) => area == 'bangkok' ? '1.3.2' : '1.2.2';

  static const double vatRate = 1.07;

  // ==================== ค่าไฟฟ้า ====================
  // ค่าคงที่เหล่านี้เป็นแหล่งความจริงเดียว — settings_rate_explanation.dart
  // ดึงตัวเลขจากที่นี่ไปโชว์ในตารางอธิบายอัตรา ห้าม hardcode ตัวเลขซ้ำที่นั่น

  // อัตราขั้นบันไดประเภทใช้เกิน 150 หน่วย/เดือน (กฟน. 1.2 / กฟภ. 1.1.2)
  static const double electricityTier1Rate = 3.2484; // 1-150 หน่วย
  static const double electricityTier2Rate = 4.2218; // 151-400 หน่วย
  static const double electricityTier3Rate = 4.4217; // 401 หน่วยขึ้นไป
  static const double electricityServiceFee = 24.62;

  // อัตรา TOU บ้านอยู่อาศัยแรงดันต่ำ (กฟน. 1.3.2 ต่ำกว่า 12 kV / กฟภ. 1.2.2
  // ต่ำกว่า 22 kV) — Peak จ.-ศ. 09:00-22:00 น. นอกนั้นรวมวันหยุดเป็น Off-Peak
  static const double touPeakRate = 5.7982;
  static const double touOffPeakRate = 2.6369;

  // อัตราขั้นบันไดสำหรับ >150 หน่วย/เดือน (กฟน. 1.2 / กฟภ. 1.1.2)
  static double _calculateEnergyRateOver150(double units) {
    double cost = 0;
    if (units <= 150) {
      cost = units * electricityTier1Rate;
    } else if (units <= 400) {
      cost = 150 * electricityTier1Rate;
      cost += (units - 150) * electricityTier2Rate;
    } else {
      cost = 150 * electricityTier1Rate;
      cost += 250 * electricityTier2Rate;
      cost += (units - 400) * electricityTier3Rate;
    }
    return cost;
  }

  // ประเภทอัตราค่าไฟของมิเตอร์ปกติ (ผู้ใช้เลือกตามใบแจ้งหนี้ — UserModel.electricityTariff)
  // tariffStandard = ใช้เกิน 150 หน่วย กฟน. 1.2 / กฟภ. 1.1.2 (ค่าเริ่มต้น บ้านส่วนใหญ่ที่มิเตอร์เกิน
  //   5 แอมแปร์ หรือใช้เกิน 150 หน่วย/เดือน)
  // tariffSmall    = ใช้ไม่เกิน 150 หน่วย กฟน. 1.1 / กฟภ. 1.1.1 (มิเตอร์ไม่เกิน 5 แอมแปร์ ที่ใช้ไม่เกิน 150
  //   หน่วย/เดือนติดต่อกัน 3 เดือน)
  static const String tariffStandard = 'standard';
  static const String tariffSmall = 'small';

  // อัตราขั้นบันไดประเภทใช้ไม่เกิน 150 หน่วย (กฟน. 1.1 / กฟภ. 1.1.1)
  static const double smallTier1Rate = 2.3488; // 1-15 หน่วย
  static const double smallTier2Rate = 2.9882; // 16-25 หน่วย
  static const double smallTier3Rate = 3.2405; // 26-35 หน่วย
  static const double smallTier4Rate = 3.6237; // 36-100 หน่วย
  static const double smallTier5Rate = 3.7171; // 101-150 หน่วย
  static const double smallTier6Rate = 4.2218; // 151-400 หน่วย
  static const double smallTier7Rate = 4.4217; // 401 หน่วยขึ้นไป
  static const double smallServiceFee = 8.19;

  static double _calculateEnergyRateSmall(double units) {
    // (หน่วยสูงสุดของขั้น, อัตรา) ไล่จากขั้นแรก
    const tiers = [
      (15.0, smallTier1Rate),
      (25.0, smallTier2Rate),
      (35.0, smallTier3Rate),
      (100.0, smallTier4Rate),
      (150.0, smallTier5Rate),
      (400.0, smallTier6Rate),
      (double.infinity, smallTier7Rate),
    ];
    double cost = 0;
    double lower = 0;
    for (final (upper, rate) in tiers) {
      if (units <= lower) break;
      cost += ((units < upper ? units : upper) - lower) * rate;
      lower = upper;
    }
    return cost;
  }

  // คำนวณค่าไฟฟ้าแบบปกติ
  // area: 'bangkok' = MEA, 'province' = PEA (ทั้งสองใช้ตารางอัตราเดียวกัน)
  // tariff: ประเภทอัตรา (ดู tariffStandard/tariffSmall) ไม่ส่ง = ใช้เกิน 150 หน่วย
  static Future<double> calculateElectricity(
    double units,
    String area, {
    String tariff = tariffStandard,
  }) async {
    if (units <= 0) return 0;

    final ftRate = await getFtRate();
    final isSmall = tariff == tariffSmall;
    double energyCost = isSmall
        ? _calculateEnergyRateSmall(units)
        : _calculateEnergyRateOver150(units);
    double serviceFee = isSmall ? smallServiceFee : electricityServiceFee;

    double ftCost = units * ftRate;
    double total = (energyCost + serviceFee + ftCost) * vatRate;

    return double.parse(total.toStringAsFixed(2));
  }

  // คำนวณค่าไฟฟ้าแบบ TOU
  static Future<double> calculateElectricityTOU({
    required double peakUnits,
    required double offPeakUnits,
  }) async {
    if (peakUnits <= 0 && offPeakUnits <= 0) return 0;

    final ftRate = await getFtRate();
    double totalUnits = peakUnits + offPeakUnits;

    double energyCost =
        (peakUnits * touPeakRate) + (offPeakUnits * touOffPeakRate);
    // ค่าบริการ TOU บ้านอยู่อาศัย (แรงดันต่ำกว่า 22kV) ตามประกาศ กฟน./กฟภ.
    // คือ 24.62 บาท เท่ากับประเภท 1.2 ปกติ ไม่ใช่ 38.22 (ค่านั้นเป็นของ
    // ผู้ใช้ไฟฟ้าประเภทอื่น) — ตรวจเทียบกับเว็บคำนวณค่าไฟทางการแล้ว
    const double serviceFee = electricityServiceFee;
    double ftCost = totalUnits * ftRate;

    double total = (energyCost + serviceFee + ftCost) * vatRate;

    return double.parse(total.toStringAsFixed(2));
  }

  // คำนวณค่าไฟตามประเภทมิเตอร์ — TOU ใช้ peakUnits/offPeakUnits,
  // มิเตอร์ปกติใช้ units ตามประเภทอัตรา [tariff] (TOU ไม่ใช้ค่านี้)
  static Future<double> calculateElectricityByType({
    required double units,
    required String meterType,
    required String area,
    double peakUnits = 0,
    double offPeakUnits = 0,
    String tariff = tariffStandard,
  }) async {
    if (meterType == 'tou') {
      return calculateElectricityTOU(
        peakUnits: peakUnits,
        offPeakUnits: offPeakUnits,
      );
    } else {
      return calculateElectricity(units, area, tariff: tariff);
    }
  }
  // ==================== ค่าน้ำประปา ====================

  // อัตราขั้นบันได MWA (กปน. กรุงเทพฯ)
  static const double waterMwaTier1 = 8.50; // 1-30 หน่วย
  static const double waterMwaTier2 = 10.03; // 31-40 หน่วย
  static const double waterMwaTier3 = 10.35; // 41-50 หน่วย
  static const double waterMwaTier4 = 10.68; // 51-60 หน่วย
  static const double waterMwaTier5 = 11.00; // 61-70 หน่วย
  static const double waterMwaTier6 = 11.33; // 71-80 หน่วย
  static const double waterMwaTier7 = 12.50; // 81-90 หน่วย
  static const double waterMwaTier8 = 12.82; // 91-100 หน่วย
  static const double waterMwaTier9 = 13.15; // 101-120 หน่วย
  static const double waterMwaTier10 = 13.47; // 121-160 หน่วย
  static const double waterMwaTier11 = 13.80; // 161-200 หน่วย
  static const double waterMwaTier12 = 14.45; // 201 หน่วยขึ้นไป
  // ค่าบริการรายเดือนของมาตรวัดน้ำขนาด ½ นิ้ว (บ้านทั่วไป) — มาตรใหญ่กว่านี้
  // ค่าบริการสูงขึ้นตามขนาด แอปไม่ได้ถามขนาดมาตร
  static const double waterMwaServiceFee = 25.00;
  static const double waterMwaRawWaterFee = 0.15;

  static double calculateWaterMWA(double units) {
    if (units <= 0) return 0;
    double cost = 0;

    if (units <= 30) {
      cost = units * waterMwaTier1;
    } else if (units <= 40) {
      cost = 30 * waterMwaTier1;
      cost += (units - 30) * waterMwaTier2;
    } else if (units <= 50) {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += (units - 40) * waterMwaTier3;
    } else if (units <= 60) {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += 10 * waterMwaTier3;
      cost += (units - 50) * waterMwaTier4;
    } else if (units <= 70) {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += 10 * waterMwaTier3;
      cost += 10 * waterMwaTier4;
      cost += (units - 60) * waterMwaTier5;
    } else if (units <= 80) {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += 10 * waterMwaTier3;
      cost += 10 * waterMwaTier4;
      cost += 10 * waterMwaTier5;
      cost += (units - 70) * waterMwaTier6;
    } else if (units <= 90) {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += 10 * waterMwaTier3;
      cost += 10 * waterMwaTier4;
      cost += 10 * waterMwaTier5;
      cost += 10 * waterMwaTier6;
      cost += (units - 80) * waterMwaTier7;
    } else if (units <= 100) {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += 10 * waterMwaTier3;
      cost += 10 * waterMwaTier4;
      cost += 10 * waterMwaTier5;
      cost += 10 * waterMwaTier6;
      cost += 10 * waterMwaTier7;
      cost += (units - 90) * waterMwaTier8;
    } else if (units <= 120) {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += 10 * waterMwaTier3;
      cost += 10 * waterMwaTier4;
      cost += 10 * waterMwaTier5;
      cost += 10 * waterMwaTier6;
      cost += 10 * waterMwaTier7;
      cost += 10 * waterMwaTier8;
      cost += (units - 100) * waterMwaTier9;
    } else if (units <= 160) {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += 10 * waterMwaTier3;
      cost += 10 * waterMwaTier4;
      cost += 10 * waterMwaTier5;
      cost += 10 * waterMwaTier6;
      cost += 10 * waterMwaTier7;
      cost += 10 * waterMwaTier8;
      cost += 20 * waterMwaTier9;
      cost += (units - 120) * waterMwaTier10;
    } else if (units <= 200) {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += 10 * waterMwaTier3;
      cost += 10 * waterMwaTier4;
      cost += 10 * waterMwaTier5;
      cost += 10 * waterMwaTier6;
      cost += 10 * waterMwaTier7;
      cost += 10 * waterMwaTier8;
      cost += 20 * waterMwaTier9;
      cost += 40 * waterMwaTier10;
      cost += (units - 160) * waterMwaTier11;
    } else {
      cost = 30 * waterMwaTier1;
      cost += 10 * waterMwaTier2;
      cost += 10 * waterMwaTier3;
      cost += 10 * waterMwaTier4;
      cost += 10 * waterMwaTier5;
      cost += 10 * waterMwaTier6;
      cost += 10 * waterMwaTier7;
      cost += 10 * waterMwaTier8;
      cost += 20 * waterMwaTier9;
      cost += 40 * waterMwaTier10;
      cost += 40 * waterMwaTier11;
      cost += (units - 200) * waterMwaTier12;
    }

    double serviceFee = waterMwaServiceFee;
    double rawWaterFee = units * waterMwaRawWaterFee;
    // ไม่มีค่าน้ำขั้นต่ำ — กปน. ยกเลิกค่าน้ำขั้นต่ำของผู้ใช้น้ำที่พักอาศัย (R1)
    // ตั้งแต่งวดการอ่านน้ำ 1 เม.ย. 2558
    double subtotal = cost + serviceFee + rawWaterFee;

    double total = subtotal * vatRate;

    return double.parse(total.toStringAsFixed(2));
  }

  // อัตราขั้นบันได PWA (กปภ. ต่างจังหวัด)
  static const double waterPwaTier1 = 10.20; // 1-10 หน่วย
  static const double waterPwaTier2 = 16.00; // 11-20 หน่วย
  static const double waterPwaTier3 = 19.00; // 21-30 หน่วย
  static const double waterPwaTier4 = 21.20; // 31-50 หน่วย
  static const double waterPwaTier5 = 21.60; // 51-80 หน่วย
  static const double waterPwaTier6 = 21.65; // 81-100 หน่วย
  static const double waterPwaTier7 = 21.70; // 101-300 หน่วย
  static const double waterPwaTier8 = 21.75; // 301-1,000 หน่วย
  static const double waterPwaTier9 = 21.80; // 1,001-2,000 หน่วย
  static const double waterPwaTier10 = 21.85; // 2,001-3,000 หน่วย
  static const double waterPwaTier11 = 21.90; // 3,001 หน่วยขึ้นไป
  // ค่าบริการรายเดือนของมาตรวัดน้ำขนาด ½ นิ้ว (บ้านทั่วไป)
  static const double waterPwaServiceFee = 30.00;

  // PWA (ต่างจังหวัด)
  // อ้างอิงตารางหมายเลข 3 (กปภ.สาขาอื่นทั่วประเทศ) จาก pwa.co.th เพราะ
  // ครอบคลุมสาขาส่วนใหญ่ของประเทศ (ยกเว้นบางสาขาในตารางหมายเลข 1, 2 ที่มี
  // อัตราของตัวเองต่างหาก ซึ่งแอปนี้ไม่ได้แยกตามสาขา)
  static double calculateWaterPWA(double units) {
    if (units <= 0) return 0;
    double cost = 0;

    // ประเภท 1 ที่อยู่อาศัย: ใช้อัตรานี้เฉพาะหน่วยที่ 1-50 เท่านั้น
    if (units <= 10) {
      cost = units * waterPwaTier1;
    } else if (units <= 20) {
      cost = 10 * waterPwaTier1;
      cost += (units - 10) * waterPwaTier2;
    } else if (units <= 30) {
      cost = 10 * waterPwaTier1;
      cost += 10 * waterPwaTier2;
      cost += (units - 20) * waterPwaTier3;
    } else if (units <= 50) {
      cost = 10 * waterPwaTier1;
      cost += 10 * waterPwaTier2;
      cost += 10 * waterPwaTier3;
      cost += (units - 30) * waterPwaTier4;
    } else {
      // เดือนไหนใช้เกิน 50 หน่วย กปภ. จะคิดหน่วยที่ 51 เป็นต้นไปด้วย
      // อัตราประเภท 2 (ราชการ/ธุรกิจขนาดเล็ก) แทน ไม่ใช่อัตราที่อยู่อาศัย
      // ต่อเนื่อง — หน่วยที่ 1-50 ยังคงคิดอัตราประเภท 1 เดิมตามปกติ
      cost = 10 * waterPwaTier1;
      cost += 10 * waterPwaTier2;
      cost += 10 * waterPwaTier3;
      cost += 20 * waterPwaTier4;

      if (units <= 80) {
        cost += (units - 50) * waterPwaTier5;
      } else if (units <= 100) {
        cost += 30 * waterPwaTier5;
        cost += (units - 80) * waterPwaTier6;
      } else if (units <= 300) {
        cost += 30 * waterPwaTier5;
        cost += 20 * waterPwaTier6;
        cost += (units - 100) * waterPwaTier7;
      } else if (units <= 1000) {
        cost += 30 * waterPwaTier5;
        cost += 20 * waterPwaTier6;
        cost += 200 * waterPwaTier7;
        cost += (units - 300) * waterPwaTier8;
      } else if (units <= 2000) {
        cost += 30 * waterPwaTier5;
        cost += 20 * waterPwaTier6;
        cost += 200 * waterPwaTier7;
        cost += 700 * waterPwaTier8;
        cost += (units - 1000) * waterPwaTier9;
      } else if (units <= 3000) {
        cost += 30 * waterPwaTier5;
        cost += 20 * waterPwaTier6;
        cost += 200 * waterPwaTier7;
        cost += 700 * waterPwaTier8;
        cost += 1000 * waterPwaTier9;
        cost += (units - 2000) * waterPwaTier10;
      } else {
        cost += 30 * waterPwaTier5;
        cost += 20 * waterPwaTier6;
        cost += 200 * waterPwaTier7;
        cost += 700 * waterPwaTier8;
        cost += 1000 * waterPwaTier9;
        cost += 1000 * waterPwaTier10;
        cost += (units - 3000) * waterPwaTier11;
      }
    }

    double serviceFee = waterPwaServiceFee;
    // ตารางอัตราของ กปภ. กำหนดค่าน้ำขั้นต่ำเฉพาะประเภท 2 และ 3 ประเภทที่อยู่
    // อาศัยไม่มีขั้นต่ำ
    double subtotal = cost + serviceFee;

    double total = subtotal * vatRate;

    return double.parse(total.toStringAsFixed(2));
  }

  // area 'bangkok' = กปน. (MWA), อื่นๆ = กปภ. (PWA)
  static double calculateWater(double units, String area) {
    if (area == 'bangkok') {
      return calculateWaterMWA(units);
    } else {
      return calculateWaterPWA(units);
    }
  }

  // หน่วยที่ใช้ = เลขใหม่ - เลขเดิม ปัดทศนิยม 2 ตำแหน่ง
  // คืน 0 เมื่อเลขใหม่ไม่มากกว่าเลขเดิม (ไม่มีทางได้ค่าติดลบ)
  static double calculateUsed(double current, double previous) {
    if (current <= previous) return 0;
    return double.parse((current - previous).toStringAsFixed(2));
  }
}