class EnergyForecaster {
  // ==================== Moving Average ====================
  // ใช้พยากรณ์ยอดบิลก่อนสิ้นรอบเดือนปัจจุบัน
  // โดยคำนวณอัตราการใช้เฉลี่ยต่อวัน แล้วประมาณวันที่เหลือ

  static double movingAverage({
    required List<double> dailyUsage, // ข้อมูลการใช้งานรายวัน
    required int remainingDays, // จำนวนวันที่เหลือในรอบบิล
    required double currentTotal, // ยอดที่ใช้ไปแล้วในรอบนี้
  }) {
    if (dailyUsage.isEmpty) return currentTotal;

    // คำนวณค่าเฉลี่ยต่อวัน
    // SMA = (X1 + X2 + ... + Xn) / n
    double sum = dailyUsage.reduce((a, b) => a + b);
    double avgPerDay = sum / dailyUsage.length;

    // พยากรณ์ยอดรวมสิ้นเดือน
    // = ยอดที่ใช้จริงแล้ว + (ค่าเฉลี่ยต่อวัน × วันที่เหลือ)
    double forecast = currentTotal + (avgPerDay * remainingDays);

    return double.parse(forecast.toStringAsFixed(2));
  }

  // ==================== Linear Regression ====================
  // ใช้พยากรณ์แนวโน้มค่าใช้จ่ายในเดือนถัดไป
  // โดยใช้ข้อมูลย้อนหลังหลายเดือนเป็น training data

  static double linearRegression({
    required List<double> monthlyValues, // ค่าใช้จ่ายย้อนหลังรายเดือน
    required int forecastMonth, // เดือนที่ต้องการพยากรณ์
  }) {
    if (monthlyValues.isEmpty) return 0;
    if (monthlyValues.length == 1) return monthlyValues[0];

    int n = monthlyValues.length;

    // สร้างข้อมูล X (เดือนที่ 1, 2, 3, ...)
    // และ Y (ค่าใช้จ่ายแต่ละเดือน)
    double sumX = 0;
    double sumY = 0;
    double sumXY = 0;
    double sumX2 = 0;

    for (int i = 0; i < n; i++) {
      double x = (i + 1).toDouble();
      double y = monthlyValues[i];

      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }

    // คำนวณค่า b (ความชัน)
    // b = (n × ΣXY - ΣX × ΣY) / (n × ΣX² - (ΣX)²)
    double b = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);

    // คำนวณค่า a (จุดตัดแกน Y)
    // a = (ΣY - b × ΣX) / n
    double a = (sumY - b * sumX) / n;

    // พยากรณ์ค่าในเดือนที่ต้องการ
    // Y = a + b × X
    double forecast = a + b * forecastMonth;

    // ไม่ให้ค่าติดลบ
    if (forecast < 0) forecast = 0;

    return double.parse(forecast.toStringAsFixed(2));
  }

  // ==================== ฟังก์ชันช่วย ====================

  // พยากรณ์ยอดค่าไฟสิ้นเดือน (Moving Average)
  static Map<String, double> forecastCurrentMonth({
    required List<double> dailyElectricityUsage,
    required List<double> dailyWaterUsage,
    required double currentElectricityCost,
    required double currentWaterCost,
    required int remainingDays,
  }) {
    double forecastElectricity = movingAverage(
      dailyUsage: dailyElectricityUsage,
      remainingDays: remainingDays,
      currentTotal: currentElectricityCost,
    );

    double forecastWater = movingAverage(
      dailyUsage: dailyWaterUsage,
      remainingDays: remainingDays,
      currentTotal: currentWaterCost,
    );

    return {
      'electricity': forecastElectricity,
      'water': forecastWater,
      'total': forecastElectricity + forecastWater,
    };
  }

  // พยากรณ์แนวโน้มเดือนถัดไป (Linear Regression)
  static Map<String, double> forecastNextMonth({
    required List<double> monthlyElectricityCosts,
    required List<double> monthlyWaterCosts,
  }) {
    int nextMonth = monthlyElectricityCosts.length + 1;

    double forecastElectricity = linearRegression(
      monthlyValues: monthlyElectricityCosts,
      forecastMonth: nextMonth,
    );

    double forecastWater = linearRegression(
      monthlyValues: monthlyWaterCosts,
      forecastMonth: nextMonth,
    );

    return {
      'electricity': forecastElectricity,
      'water': forecastWater,
      'total': forecastElectricity + forecastWater,
    };
  }

  // คำนวณจำนวนวันที่เหลือในรอบบิล
  static int getRemainingDays(DateTime now, int billingDay) {
    DateTime billingDate = DateTime(now.year, now.month, billingDay);

    // ถ้าวันตัดบิลผ่านไปแล้วในเดือนนี้ ให้ดูเดือนหน้า
    if (now.day > billingDay) {
      billingDate = DateTime(now.year, now.month + 1, billingDay);
    }

    return billingDate.difference(now).inDays;
  }

  // คำนวณวันที่ผ่านมาในรอบบิล
  static int getDaysElapsed(DateTime now, int billingDay) {
    DateTime billingDate = DateTime(now.year, now.month, billingDay);

    // ถ้าวันตัดบิลผ่านไปแล้ว ให้นับจากเดือนก่อน
    if (now.day > billingDay) {
      return now.day - billingDay;
    } else {
      DateTime prevBillingDate =
          DateTime(now.year, now.month - 1, billingDay);
      return now.difference(prevBillingDate).inDays;
    }
  }
}