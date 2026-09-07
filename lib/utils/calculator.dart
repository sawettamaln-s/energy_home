import 'package:cloud_firestore/cloud_firestore.dart';

class EnergyCalculator {
  static Future<double> getFtRate() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('electricity_rates')
          .get();
      return (doc.data()?['ft_rate'] ?? 0.1623).toDouble();
    } catch (e) {
      return 0.1623;
    }
  }

  static const double vatRate = 1.07;

  // ==================== ค่าไฟฟ้า ====================
  // ค่าคงที่เหล่านี้เป็นแหล่งความจริงเดียว — settings_rate_explanation.dart
  // ดึงตัวเลขจากที่นี่ไปโชว์ในตารางอธิบายอัตรา ห้าม hardcode ตัวเลขซ้ำที่นั่น

  // อัตราขั้นบันไดประเภท 1.2 / 1.1.2 (ใช้เกิน 150 หน่วย/เดือน)
  static const double electricityTier1Rate = 3.2484; // 1-150 หน่วย
  static const double electricityTier2Rate = 4.2218; // 151-400 หน่วย
  static const double electricityTier3Rate = 4.4217; // 401 หน่วยขึ้นไป
  static const double electricityServiceFee = 24.62;

  // อัตรา TOU
  static const double touPeakRate = 5.7982;
  static const double touOffPeakRate = 2.6369;

  // อัตราขั้นบันไดสำหรับ >150 หน่วย/เดือน (ประเภท 1.2 / 1.1.2)
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

  // คำนวณค่าไฟฟ้าแบบปกติ
  // area: 'bangkok' = MEA, 'province' = PEA
  // หมายเหตุ: แอปเซตค่าไฟทั้ง MEA และ PEA ไว้ที่ประเภท 1.2 / 1.1.2 (ใช้เกิน
  // 150 หน่วยต่อเดือน) เป็นค่าเริ่มต้นเสมอ เพราะบ้านส่วนใหญ่ในปัจจุบันมีแอร์
  // และเครื่องทำน้ำอุ่น ทำให้ใช้ไฟฟ้าเกิน 150 หน่วยต่อเดือนอยู่แล้ว
  static Future<double> calculateElectricity(
      double units, String area) async {
    if (units <= 0) return 0;

    final ftRate = await getFtRate();
    // ทั้ง MEA (bangkok) และ PEA (province) ใช้อัตราประเภท 1.2 / 1.1.2 เสมอ
    double energyCost = _calculateEnergyRateOver150(units);
    double serviceFee = electricityServiceFee;

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
    // ผู้ใช้ไฟฟ้าประเภทอื่น) — แก้ตามที่เทียบกับเว็บคำนวณค่าไฟทางการแล้ว
    const double serviceFee = electricityServiceFee;
    double ftCost = totalUnits * ftRate;

    double total = (energyCost + serviceFee + ftCost) * vatRate;

    return double.parse(total.toStringAsFixed(2));
  }

  // คำนวณค่าไฟตามประเภทมิเตอร์
  static Future<double> calculateElectricityByType({
    required double units,
    required String meterType,
    required String area,
    double peakUnits = 0,
    double offPeakUnits = 0,
  }) async {
    if (meterType == 'tou') {
      return calculateElectricityTOU(
        peakUnits: peakUnits,
        offPeakUnits: offPeakUnits,
      );
    } else {
      return calculateElectricity(units, area);
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
  static const double waterMwaServiceFee = 25.00;
  static const double waterMwaRawWaterFee = 0.15;
  static const double waterMwaMinimum = 45.00;

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
    double subtotal = cost + serviceFee + rawWaterFee;

    // ค่าน้ำขั้นต่ำของ กปน. คือ 45 บาท/เดือน (ก่อน VAT) สำหรับผู้ใช้น้ำ
    // ช่วง 0-30 หน่วย ตามประกาศอัตราค่าน้ำ กปน. — กันเคสใช้น้ำน้อยมากๆ
    // ที่คำนวณตามขั้นบันไดแล้วต่ำกว่าค่าขั้นต่ำที่ กปน. เรียกเก็บจริง
    if (subtotal < waterMwaMinimum) {
      subtotal = waterMwaMinimum;
    }

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
  static const double waterPwaServiceFee = 30.00;
  static const double waterPwaMinimum = 50.00;

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
    double subtotal = cost + serviceFee;

    // ค่าน้ำขั้นต่ำของ กปภ. สำหรับผู้ใช้น้ำประเภทที่อยู่อาศัย คือ 50 บาท/เดือน
    // (ก่อน VAT) กันเคสใช้น้ำน้อยมากๆ ที่คำนวณได้ต่ำกว่าค่าขั้นต่ำจริง
    if (subtotal < waterPwaMinimum) {
      subtotal = waterPwaMinimum;
    }

    double total = subtotal * vatRate;

    return double.parse(total.toStringAsFixed(2));
  }

  static double calculateWater(double units, String area) {
    if (area == 'bangkok') {
      return calculateWaterMWA(units);
    } else {
      return calculateWaterPWA(units);
    }
  }

  static double calculateUsed(double current, double previous) {
    if (current <= previous) return 0;
    return double.parse((current - previous).toStringAsFixed(2));
  }
}