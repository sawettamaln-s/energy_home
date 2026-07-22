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

  // ==================== ค่าไฟฟ้า ====================

  // อัตราขั้นบันไดสำหรับ ≤150 หน่วย/เดือน (ประเภท 1.1 / 1.1.1)
  static double _calculateEnergyRateUnder150(double units) {
    double cost = 0;
    if (units <= 15) {
      cost = units * 2.3488;
    } else if (units <= 25) {
      cost = 15 * 2.3488;
      cost += (units - 15) * 2.9882;
    } else if (units <= 35) {
      cost = 15 * 2.3488;
      cost += 10 * 2.9882;
      cost += (units - 25) * 3.2405;
    } else if (units <= 100) {
      cost = 15 * 2.3488;
      cost += 10 * 2.9882;
      cost += 10 * 3.2405;
      cost += (units - 35) * 3.6237;
    } else {
      // 101-150
      cost = 15 * 2.3488;
      cost += 10 * 2.9882;
      cost += 10 * 3.2405;
      cost += 65 * 3.6237;
      cost += (units - 100) * 3.7171;
    }
    return cost;
  }

  // อัตราขั้นบันไดสำหรับ >150 หน่วย/เดือน (ประเภท 1.2 / 1.1.2)
  static double _calculateEnergyRateOver150(double units) {
    double cost = 0;
    if (units <= 150) {
      cost = units * 3.2484;
    } else if (units <= 400) {
      cost = 150 * 3.2484;
      cost += (units - 150) * 4.2218;
    } else {
      cost = 150 * 3.2484;
      cost += 250 * 4.2218;
      cost += (units - 400) * 4.4217;
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
    double serviceFee = 24.62;

    double ftCost = units * ftRate;
    double total = (energyCost + serviceFee + ftCost) * 1.07;

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

    double energyCost = (peakUnits * 5.7982) + (offPeakUnits * 2.6369);
    // ค่าบริการ TOU บ้านอยู่อาศัย (แรงดันต่ำกว่า 22kV) ตามประกาศ กฟน./กฟภ.
    // คือ 24.62 บาท เท่ากับประเภท 1.2 ปกติ ไม่ใช่ 38.22 (ค่านั้นเป็นของ
    // ผู้ใช้ไฟฟ้าประเภทอื่น) — แก้ตามที่เทียบกับเว็บคำนวณค่าไฟทางการแล้ว
    const double serviceFee = 24.62;
    double ftCost = totalUnits * ftRate;

    double total = (energyCost + serviceFee + ftCost) * 1.07;

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

  static double calculateWaterMWA(double units) {
    if (units <= 0) return 0;
    double cost = 0;

    if (units <= 30) {
      cost = units * 8.50;
    } else if (units <= 40) {
      cost = 30 * 8.50;
      cost += (units - 30) * 10.03;
    } else if (units <= 50) {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += (units - 40) * 10.35;
    } else if (units <= 60) {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += 10 * 10.35;
      cost += (units - 50) * 10.68;
    } else if (units <= 70) {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += 10 * 10.35;
      cost += 10 * 10.68;
      cost += (units - 60) * 11.00;
    } else if (units <= 80) {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += 10 * 10.35;
      cost += 10 * 10.68;
      cost += 10 * 11.00;
      cost += (units - 70) * 11.33;
    } else if (units <= 90) {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += 10 * 10.35;
      cost += 10 * 10.68;
      cost += 10 * 11.00;
      cost += 10 * 11.33;
      cost += (units - 80) * 12.50;
    } else if (units <= 100) {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += 10 * 10.35;
      cost += 10 * 10.68;
      cost += 10 * 11.00;
      cost += 10 * 11.33;
      cost += 10 * 12.50;
      cost += (units - 90) * 12.82;
    } else if (units <= 120) {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += 10 * 10.35;
      cost += 10 * 10.68;
      cost += 10 * 11.00;
      cost += 10 * 11.33;
      cost += 10 * 12.50;
      cost += 10 * 12.82;
      cost += (units - 100) * 13.15;
    } else if (units <= 160) {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += 10 * 10.35;
      cost += 10 * 10.68;
      cost += 10 * 11.00;
      cost += 10 * 11.33;
      cost += 10 * 12.50;
      cost += 10 * 12.82;
      cost += 20 * 13.15;
      cost += (units - 120) * 13.47;
    } else if (units <= 200) {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += 10 * 10.35;
      cost += 10 * 10.68;
      cost += 10 * 11.00;
      cost += 10 * 11.33;
      cost += 10 * 12.50;
      cost += 10 * 12.82;
      cost += 20 * 13.15;
      cost += 40 * 13.47;
      cost += (units - 160) * 13.80;
    } else {
      cost = 30 * 8.50;
      cost += 10 * 10.03;
      cost += 10 * 10.35;
      cost += 10 * 10.68;
      cost += 10 * 11.00;
      cost += 10 * 11.33;
      cost += 10 * 12.50;
      cost += 10 * 12.82;
      cost += 20 * 13.15;
      cost += 40 * 13.47;
      cost += 40 * 13.80;
      cost += (units - 200) * 14.45;
    }

    double serviceFee = 25.00;
    double rawWaterFee = units * 0.15;
    double subtotal = cost + serviceFee + rawWaterFee;

    // ค่าน้ำขั้นต่ำของ กปน. คือ 45 บาท/เดือน (ก่อน VAT) สำหรับผู้ใช้น้ำ
    // ช่วง 0-30 หน่วย ตามประกาศอัตราค่าน้ำ กปน. — กันเคสใช้น้ำน้อยมากๆ
    // ที่คำนวณตามขั้นบันไดแล้วต่ำกว่าค่าขั้นต่ำที่ กปน. เรียกเก็บจริง
    if (subtotal < 45.00) {
      subtotal = 45.00;
    }

    double total = subtotal * 1.07;

    return double.parse(total.toStringAsFixed(2));
  }

  // PWA (ต่างจังหวัด)
  // อ้างอิงตารางหมายเลข 3 (กปภ.สาขาอื่นทั่วประเทศ) จาก pwa.co.th เพราะ
  // ครอบคลุมสาขาส่วนใหญ่ของประเทศ (ยกเว้นบางสาขาในตารางหมายเลข 1, 2 ที่มี
  // อัตราของตัวเองต่างหาก ซึ่งแอปนี้ไม่ได้แยกตามสาขา)
  static double calculateWaterPWA(double units) {
    if (units <= 0) return 0;
    double cost = 0;

    // ประเภท 1 ที่อยู่อาศัย: ใช้อัตรานี้เฉพาะหน่วยที่ 1-50 เท่านั้น
    if (units <= 10) {
      cost = units * 10.20;
    } else if (units <= 20) {
      cost = 10 * 10.20;
      cost += (units - 10) * 16.00;
    } else if (units <= 30) {
      cost = 10 * 10.20;
      cost += 10 * 16.00;
      cost += (units - 20) * 19.00;
    } else if (units <= 50) {
      cost = 10 * 10.20;
      cost += 10 * 16.00;
      cost += 10 * 19.00;
      cost += (units - 30) * 21.20;
    } else {
      // เดือนไหนใช้เกิน 50 หน่วย กปภ. จะคิดหน่วยที่ 51 เป็นต้นไปด้วย
      // อัตราประเภท 2 (ราชการ/ธุรกิจขนาดเล็ก) แทน ไม่ใช่อัตราที่อยู่อาศัย
      // ต่อเนื่อง — หน่วยที่ 1-50 ยังคงคิดอัตราประเภท 1 เดิมตามปกติ
      cost = 10 * 10.20;
      cost += 10 * 16.00;
      cost += 10 * 19.00;
      cost += 20 * 21.20;

      if (units <= 80) {
        cost += (units - 50) * 21.60;
      } else if (units <= 100) {
        cost += 30 * 21.60;
        cost += (units - 80) * 21.65;
      } else if (units <= 300) {
        cost += 30 * 21.60;
        cost += 20 * 21.65;
        cost += (units - 100) * 21.70;
      } else if (units <= 1000) {
        cost += 30 * 21.60;
        cost += 20 * 21.65;
        cost += 200 * 21.70;
        cost += (units - 300) * 21.75;
      } else if (units <= 2000) {
        cost += 30 * 21.60;
        cost += 20 * 21.65;
        cost += 200 * 21.70;
        cost += 700 * 21.75;
        cost += (units - 1000) * 21.80;
      } else if (units <= 3000) {
        cost += 30 * 21.60;
        cost += 20 * 21.65;
        cost += 200 * 21.70;
        cost += 700 * 21.75;
        cost += 1000 * 21.80;
        cost += (units - 2000) * 21.85;
      } else {
        cost += 30 * 21.60;
        cost += 20 * 21.65;
        cost += 200 * 21.70;
        cost += 700 * 21.75;
        cost += 1000 * 21.80;
        cost += 1000 * 21.85;
        cost += (units - 3000) * 21.90;
      }
    }

    double serviceFee = 30.00;
    double subtotal = cost + serviceFee;

    // ค่าน้ำขั้นต่ำของ กปภ. สำหรับผู้ใช้น้ำประเภทที่อยู่อาศัย คือ 50 บาท/เดือน
    // (ก่อน VAT) กันเคสใช้น้ำน้อยมากๆ ที่คำนวณได้ต่ำกว่าค่าขั้นต่ำจริง
    if (subtotal < 50.00) {
      subtotal = 50.00;
    }

    double total = subtotal * 1.07;

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