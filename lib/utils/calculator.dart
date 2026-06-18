import 'package:cloud_firestore/cloud_firestore.dart';

class EnergyCalculator {
  // ดึงค่า Ft จาก Firestore document กลาง
  static Future<double> getFtRate() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('electricity_rates')
          .get();
      return (doc.data()?['ft_rate'] ?? 0.1623).toDouble();
    } catch (e) {
      return 0.1623; // fallback ค่าปัจจุบัน พ.ค.-ส.ค. 2569
    }
  }

  // ==================== ค่าไฟฟ้า ====================

  // คำนวณค่าพลังงานไฟฟ้าตามขั้นบันได (ก่อนบวกค่าบริการ Ft VAT)
  // MEA และ PEA ใช้อัตราขั้นบันไดเหมือนกัน
  static double _calculateEnergyRate(double units) {
    double cost = 0;
    if (units <= 0) return 0;

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
    } else if (units <= 150) {
      cost = 15 * 2.3488;
      cost += 10 * 2.9882;
      cost += 10 * 3.2405;
      cost += 65 * 3.6237;
      cost += (units - 100) * 3.7171;
    } else if (units <= 400) {
      cost = 15 * 2.3488;
      cost += 10 * 2.9882;
      cost += 10 * 3.2405;
      cost += 65 * 3.6237;
      cost += 50 * 3.7171;
      cost += (units - 150) * 4.2218;
    } else {
      cost = 15 * 2.3488;
      cost += 10 * 2.9882;
      cost += 10 * 3.2405;
      cost += 65 * 3.6237;
      cost += 50 * 3.7171;
      cost += 250 * 4.2218;
      cost += (units - 400) * 4.4217;
    }

    return cost;
  }

  // คำนวณค่าบริการไฟฟ้าตามพื้นที่และหน่วยที่ใช้
  // MEA และ PEA ค่าบริการต่างกันเมื่อใช้เกิน 150 หน่วย
  static double _getServiceFee(double units, String area) {
    if (units <= 150) {
      // MEA และ PEA ค่าบริการเท่ากัน ≤150 หน่วย
      return 8.19;
    } else {
      // >150 หน่วย MEA และ PEA ต่างกัน
      return area == 'bangkok' ? 38.22 : 24.62;
    }
  }

  // คำนวณค่าไฟฟ้าแบบปกติ (อัตราขั้นบันได)
  // area: 'bangkok' = MEA, 'province' = PEA
  static Future<double> calculateElectricity(
      double units, String area, String meterSize) async {
    if (units <= 0) return 0;

    final ftRate = await getFtRate();

    double energyCost = 0;
    double serviceFee = 0;

    if (meterSize == '5a') {
      // ประเภท 1.1.1 มิเตอร์ ≤5A
      // ใช้ไม่เกิน 50 หน่วย → ค่าพลังงาน = 0 บาท
      // ใช้เกิน 50 หน่วย → คิดทุกหน่วยปกติ
      if (units <= 50) {
        energyCost = 0;
      } else {
        energyCost = _calculateEnergyRate(units);
      }
      // ค่าบริการประเภท 1.1.1
      serviceFee = units <= 150 ? 8.19 : 38.22;
    } else {
      // ประเภท 1.1.2 มิเตอร์ >5A
      // คิดค่าพลังงานทุกหน่วยเสมอ
      energyCost = _calculateEnergyRate(units);
      // ค่าบริการแยก MEA/PEA เมื่อ >150 หน่วย
      serviceFee = _getServiceFee(units, area);
    }

    double ftCost = units * ftRate;

    // สูตร: (ค่าพลังงาน + ค่าบริการ + ค่า Ft) × 1.07
    double total = (energyCost + serviceFee + ftCost) * 1.07;

    return double.parse(total.toStringAsFixed(2));
  }

  // คำนวณค่าไฟฟ้าแบบ TOU
  // On-Peak: จ-ศ 09:00-22:00
  // Off-Peak: จ-ศ 22:00-09:00 + เสาร์-อาทิตย์ + วันหยุด
  static Future<double> calculateElectricityTOU({
    required double peakUnits,
    required double offPeakUnits,
  }) async {
    if (peakUnits <= 0 && offPeakUnits <= 0) return 0;

    final ftRate = await getFtRate();
    double totalUnits = peakUnits + offPeakUnits;

    double energyCost = (peakUnits * 5.7982) + (offPeakUnits * 2.6369);
    const double serviceFee = 228.17;
    double ftCost = totalUnits * ftRate;

    // สูตร: (ค่าพลังงาน + ค่าบริการ + ค่า Ft) × 1.07
    double total = (energyCost + serviceFee + ftCost) * 1.07;

    return double.parse(total.toStringAsFixed(2));
  }

  // คำนวณค่าไฟตามประเภทมิเตอร์
  static Future<double> calculateElectricityByType({
    required double units,
    required String meterType,
    required String area,
    String meterSize = '15a',
    double peakUnits = 0,
    double offPeakUnits = 0,
  }) async {
    if (meterType == 'tou') {
      return calculateElectricityTOU(
        peakUnits: peakUnits,
        offPeakUnits: offPeakUnits,
      );
    } else {
      return calculateElectricity(units, area, meterSize);
    }
  }
  // ==================== ค่าน้ำประปา ====================
  // หน่วยเป็น ลูกบาศก์เมตร (ลบ.ม.)

  // คำนวณค่าน้ำ MWA (กรุงเทพและปริมณฑล)
  // สูตร: (ค่าน้ำ + ค่าบริการ 25 บาท + ค่าน้ำดิบ 0.15/ลบ.ม.) × 1.07
  static double calculateWaterMWA(double units) {
    if (units <= 0) return 0;

    double cost = 0;

    // อัตราขั้นบันได MWA (12 ช่วง)
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

    // บวกค่าบริการ 25 บาท + ค่าน้ำดิบ 0.15/ลบ.ม.
    double serviceFee = 25.00;
    double rawWaterFee = units * 0.15;

    // คูณ VAT 7%
    double total = (cost + serviceFee + rawWaterFee) * 1.07;

    return double.parse(total.toStringAsFixed(2));
  }

  // คำนวณค่าน้ำ PWA (ต่างจังหวัด)
  // สูตร: ค่าน้ำ × 1.07 (ไม่มีค่าบริการและค่าน้ำดิบ)
  static double calculateWaterPWA(double units) {
    if (units <= 0) return 0;

    double cost = 0;

    // อัตราขั้นบันได PWA (4 ช่วง)
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
      // 51+ ลบ.ม. อัตราประเกท (แพงมาก)
      cost = 10 * 10.20;
      cost += 10 * 16.00;
      cost += 10 * 19.00;
      cost += 20 * 21.20;
      cost += (units - 50) * 25.00; // ประมาณการ
    }

    // คูณ VAT 7% (PWA ไม่มีค่าบริการและค่าน้ำดิบ)
    double total = cost * 1.07;

    return double.parse(total.toStringAsFixed(2));
  }

  // คำนวณค่าน้ำตามพื้นที่
  static double calculateWater(double units, String area) {
    if (area == 'bangkok') {
      return calculateWaterMWA(units);
    } else {
      return calculateWaterPWA(units);
    }
  }

  // ==================== ฟังก์ชันช่วย ====================

  // คำนวณหน่วยที่ใช้จากผลต่างค่ามิเตอร์
  static double calculateUsed(double current, double previous) {
    if (current <= previous) return 0;
    return double.parse((current - previous).toStringAsFixed(2));
  }
}
