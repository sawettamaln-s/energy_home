class EnergyCalculator {
  // ==================== ค่าไฟฟ้า ====================

  // คำนวณค่าไฟแบบปกติ (อัตราขั้นบันได)
  // ใช้ได้ทั้ง MEA และ PEA เพราะอัตราเดียวกัน
  static double calculateElectricity(double units) {
    double cost = 0;

    if (units <= 0) return 0;

    // อัตราขั้นบันได
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

    // บวกค่าบริการ
    cost += 38.22;

    return double.parse(cost.toStringAsFixed(2));
  }

  // คำนวณค่าไฟแบบ TOU (Time of Use)
  static double calculateElectricityTOU({
    required double peakUnits, // หน่วยที่ใช้ช่วง Peak
    required double offPeakUnits, // หน่วยที่ใช้ช่วง Off-Peak
  }) {
    double cost = 0;

    // Peak: วันจันทร์-ศุกร์ 09:00-22:00
    cost += peakUnits * 5.7982;

    // Off-Peak: วันจันทร์-ศุกร์ 22:00-09:00 และวันหยุด
    cost += offPeakUnits * 2.6369;

    // บวกค่าบริการ TOU
    cost += 228.17;

    return double.parse(cost.toStringAsFixed(2));
  }

  // ==================== ค่าน้ำประปา ====================

  // คำนวณค่าน้ำ MWA (กรุงเทพและปริมณฑล)
  static double calculateWaterMWA(double units) {
    double cost = 0;

    if (units <= 0) return 0;

    if (units <= 30) {
      cost = units * 8.50;
    } else if (units <= 50) {
      cost = 30 * 8.50;
      cost += (units - 30) * 10.70;
    } else if (units <= 80) {
      cost = 30 * 8.50;
      cost += 20 * 10.70;
      cost += (units - 50) * 12.24;
    } else {
      cost = 30 * 8.50;
      cost += 20 * 10.70;
      cost += 30 * 12.24;
      cost += (units - 80) * 13.21;
    }

    // บวกค่าบริการ MWA
    cost += 40.00;

    return double.parse(cost.toStringAsFixed(2));
  }

  // คำนวณค่าน้ำ PWA (ต่างจังหวัด)
  static double calculateWaterPWA(double units) {
    double cost = 0;

    if (units <= 0) return 0;

    if (units <= 30) {
      cost = units * 8.50;
    } else if (units <= 50) {
      cost = 30 * 8.50;
      cost += (units - 30) * 10.70;
    } else if (units <= 80) {
      cost = 30 * 8.50;
      cost += 20 * 10.70;
      cost += (units - 50) * 12.24;
    } else {
      cost = 30 * 8.50;
      cost += 20 * 10.70;
      cost += 30 * 12.24;
      cost += (units - 80) * 13.21;
    }

    // บวกค่าบริการ PWA (ต่างจาก MWA)
    cost += 29.03;

    return double.parse(cost.toStringAsFixed(2));
  }

  // ==================== ฟังก์ชันรวม ====================

  // คำนวณค่าน้ำตามพื้นที่
  // area: 'bangkok' หรือ 'province'
  static double calculateWater(double units, String area) {
    if (area == 'bangkok') {
      return calculateWaterMWA(units);
    } else {
      return calculateWaterPWA(units);
    }
  }

  // คำนวณค่าไฟตามประเภทมิเตอร์
  // meterType: 'normal' หรือ 'tou'
  static double calculateElectricityByType({
    required double units,
    required String meterType,
    double peakUnits = 0,
    double offPeakUnits = 0,
  }) {
    if (meterType == 'tou') {
      return calculateElectricityTOU(
        peakUnits: peakUnits,
        offPeakUnits: offPeakUnits,
      );
    } else {
      return calculateElectricity(units);
    }
  }

  // คำนวณหน่วยที่ใช้จากผลต่างค่ามิเตอร์
  static double calculateUsed(double current, double previous) {
    if (current < previous) return 0;
    return double.parse((current - previous).toStringAsFixed(2));
  }
}