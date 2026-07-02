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
  // หมายเหตุ: แอปรองรับเฉพาะมิเตอร์ 15A ขึ้นไป (ประเภท 1.2) เท่านั้น
  // เพราะบ้านส่วนใหญ่ในปัจจุบันใช้มิเตอร์ขนาดนี้ ตัดการรองรับมิเตอร์ 5A (ประเภท 1.1) ออกแล้ว
  static Future<double> calculateElectricity(
      double units, String area) async {
    if (units <= 0) return 0;

    final ftRate = await getFtRate();
    double energyCost;
    double serviceFee;

    if (area == 'bangkok') {
      // MEA: มิเตอร์ 15A ขึ้นไป → ประเภท 1.2 เสมอ
      energyCost = _calculateEnergyRateOver150(units);
      serviceFee = 24.62;
    } else {
      // PEA: หน่วยที่ใช้เป็นตัวกำหนดอย่างเดียว
      if (units <= 150) {
        energyCost = _calculateEnergyRateUnder150(units);
        serviceFee = 8.19;
      } else {
        energyCost = _calculateEnergyRateOver150(units);
        serviceFee = 24.62;
      }
    }

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
    const double serviceFee = 38.22;
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
  // (ยังต้องตรวจสอบ PWA เพิ่ม - คงไว้ตามเดิมก่อน)

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
    double total = (cost + serviceFee + rawWaterFee) * 1.07;

    return double.parse(total.toStringAsFixed(2));
  }

  // PWA - คงเดิมไว้ก่อน ต้องเช็คเพิ่มทีหลัง
  static double calculateWaterPWA(double units) {
    if (units <= 0) return 0;
    double cost = 0;

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
      cost = 10 * 10.20;
      cost += 10 * 16.00;
      cost += 10 * 19.00;
      cost += 20 * 21.20;
      cost += (units - 50) * 25.00;
    }

    double serviceFee = 30.00; // เพิ่มค่าบริการตามที่เจอในรูป
    double total = (cost + serviceFee) * 1.07;

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