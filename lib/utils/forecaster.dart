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

  // =====================================================================
  // ขอบเขตรอบบิล — แหล่งความจริงเดียว (single source of truth)
  // นิยาม: รอบบิลปัจจุบัน = ตั้งแต่วันตัดรอบล่าสุดที่ผ่านมา (รวมวันนั้น)
  // ไปจนถึงวันตัดรอบครั้งถัดไป (ไม่รวมวันนั้น)
  // ถ้าวันนี้ตรงกับวันตัดรอบเป๊ะ ถือว่าวันนี้คือวันแรกของรอบใหม่
  // =====================================================================

  // คืนวันตัดรอบบิลที่ "ปลอดภัย" ของเดือน year/month ที่ระบุ
  // ถ้า billingDay เกินจำนวนวันจริงของเดือนนั้น (เช่น 31 แต่เดือนมี 30 วัน)
  // จะหล่นไปวันสุดท้ายของเดือนนั้นแทน ไม่ปล่อยให้ DateTime ดันข้ามเดือนเอง
  static DateTime _safeBillingDate(int year, int month, int billingDay) {
    // DateTime(year, month + 1, 0) = วันสุดท้ายของเดือน month
    // (การ์ดนี้ปลอดภัยเพราะ day=0/1 ไม่มีทาง overflow ข้ามเดือน)
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final safeDay = billingDay > lastDayOfMonth ? lastDayOfMonth : billingDay;
    return DateTime(year, month, safeDay);
  }

  // จุดเริ่มต้นของรอบบิลปัจจุบัน (รวมวันนี้ถ้าวันนี้ตรงกับวันตัดรอบ)
  static DateTime getCycleStart(DateTime now, int billingDay) {
    // สำคัญ: ต้องเทียบกับ "วันคัตออฟที่ clamp แล้วของเดือนนี้" ไม่ใช่
    // billingDay ดิบ เพราะถ้า billingDay เกินจำนวนวันของเดือนนี้
    // (เช่น 30 แต่ ก.พ. ปีอธิกสุรทินมีแค่ 29) คัตออฟจริงของเดือนนี้
    // จะหล่นลงมาเป็น 29 ไปแล้ว ต้องเทียบกับ 29 ไม่ใช่ 30
    final cutoffThisMonth = _safeBillingDate(now.year, now.month, billingDay);
    if (now.day >= cutoffThisMonth.day) {
      return cutoffThisMonth;
    } else {
      final prevMonth = DateTime(now.year, now.month - 1, 1);
      return _safeBillingDate(prevMonth.year, prevMonth.month, billingDay);
    }
  }

  // จุดสิ้นสุดของรอบบิลปัจจุบัน (ไม่รวมวันนี้ ถ้าวันนี้ตรงกับวันตัดรอบ)
  static DateTime getCycleEnd(DateTime now, int billingDay) {
    final cutoffThisMonth = _safeBillingDate(now.year, now.month, billingDay);
    if (now.day >= cutoffThisMonth.day) {
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      return _safeBillingDate(nextMonth.year, nextMonth.month, billingDay);
    } else {
      return cutoffThisMonth;
    }
  }

  // จุดเริ่มต้นของรอบบิล "ก่อนหน้า" รอบที่ขึ้นต้นด้วย cycleStart ที่ให้มา
  // ใช้ตอนต้องปิดบิลของรอบก่อนหน้า (ดู dashboard_screen.dart -> compileBill)
  static DateTime getPreviousCycleStart(DateTime cycleStart, int billingDay) {
    final prevMonth = DateTime(cycleStart.year, cycleStart.month - 1, 1);
    return _safeBillingDate(prevMonth.year, prevMonth.month, billingDay);
  }

  // คำนวณจำนวนวันที่เหลือในรอบบิล
  static int getRemainingDays(DateTime now, int billingDay) {
    return getCycleEnd(now, billingDay).difference(now).inDays;
  }

  // คำนวณวันที่ผ่านมาในรอบบิล
  static int getDaysElapsed(DateTime now, int billingDay) {
    return now.difference(getCycleStart(now, billingDay)).inDays;
  }
}