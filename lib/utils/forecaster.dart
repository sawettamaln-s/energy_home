class EnergyForecaster {
  // ==================== Moving Average ====================
  // ใช้คาดการณ์ยอดบิลก่อนสิ้นรอบเดือนปัจจุบัน
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

    // คาดการณ์ยอดรวมสิ้นเดือน
    // = ยอดที่ใช้จริงแล้ว + (ค่าเฉลี่ยต่อวัน × วันที่เหลือ)
    double forecast = currentTotal + (avgPerDay * remainingDays);

    return double.parse(forecast.toStringAsFixed(2));
  }

  // ==================== Linear Regression ====================
  // ใช้คาดการณ์แนวโน้มค่าใช้จ่ายในเดือนถัดไป
  // โดยใช้ข้อมูลย้อนหลังหลายเดือนเป็น training data

  static double linearRegression({
    required List<double> monthlyValues, // ค่าใช้จ่ายย้อนหลังรายเดือน
    required int forecastMonth, // เดือนที่ต้องการคาดการณ์
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

    // คาดการณ์ค่าในเดือนที่ต้องการ
    // Y = a + b × X
    double forecast = a + b * forecastMonth;

    // ไม่ให้ค่าติดลบ
    if (forecast < 0) forecast = 0;

    return double.parse(forecast.toStringAsFixed(2));
  }
    // ==================== Seasonal Curve (synthetic + จริงผสมกัน) ====================
  // ใช้คาดการณ์เดือนถัดไป โดยเอาค่าเฉลี่ยล่าสุดของ user คูณกับ "ตัวคูณตามฤดูกาล"
  // ของเคสนั้น (ดู lib/utils/seasonal_curves.dart ที่ generate มาจาก
  // tool/forecast_synth/ — ผสมข้อมูลสมมติกับข้อมูลจริงเท่าที่มี)

  static double seasonalForecast({
    required List<double> recentMonthlyValues, // ค่าใช้จ่ายย้อนหลังไม่กี่เดือนล่าสุดของ user คนนี้
    required List<int> recentMonths, // เดือนปฏิทิน (1-12) ของแต่ละค่าใน recentMonthlyValues ตำแหน่งตรงกัน
    required List<double> curve, // 12 ค่า จาก SeasonalCurves (index 0 = ม.ค.)
    required int forecastMonth, // เดือนที่จะทาย (1-12)
  }) {
    if (recentMonthlyValues.isEmpty) return 0;
    if (curve.length != 12) {
      throw ArgumentError('curve ต้องมี 12 ค่า (ม.ค.-ธ.ค.)');
    }
    if (recentMonthlyValues.length != recentMonths.length) {
      throw ArgumentError(
          'recentMonthlyValues กับ recentMonths ต้องมีความยาวเท่ากัน');
    }

    // หักผลของฤดูกาลออกจากแต่ละเดือนก่อน (deseasonalize) ก่อนเฉลี่ย — ถ้าเอา
    // ค่าดิบ (ที่ยังมีฤดูกาลของช่วงที่ผ่านมาติดอยู่) ไปเฉลี่ยตรงๆ แล้วคูณกับ
    // curve[forecastMonth] ซ้ำอีกที จะกลายเป็นใส่ฤดูกาลซ้ำสองชั้น เช่น ทายจาก
    // เดือนที่ใช้ไฟพีค (เม.ย.-พ.ค.) ไปหาเดือนที่เบากว่า (ก.ค.) จะทายสูงเกินจริง
    // ไปได้ถึง ~20% ต้องหารด้วย curve ของเดือนนั้นๆ ก่อน ถึงจะได้ "ระดับการใช้
    // จริง" ที่หักฤดูกาลออกแล้ว แล้วค่อยคูณกลับด้วย curve ของเดือนเป้าหมาย
    double deseasonalizedSum = 0;
    for (int i = 0; i < recentMonthlyValues.length; i++) {
      final monthFactor = curve[recentMonths[i] - 1];
      deseasonalizedSum += monthFactor > 0
          ? recentMonthlyValues[i] / monthFactor
          : recentMonthlyValues[i];
    }
    double baseLevel = deseasonalizedSum / recentMonthlyValues.length;

    double factor = curve[forecastMonth - 1];
    double forecast = baseLevel * factor;

    return double.parse(forecast.toStringAsFixed(2));
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
  static DateTime safeBillingDate(int year, int month, int billingDay) {
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
    final cutoffThisMonth = safeBillingDate(now.year, now.month, billingDay);
    if (now.day >= cutoffThisMonth.day) {
      return cutoffThisMonth;
    } else {
      final prevMonth = DateTime(now.year, now.month - 1, 1);
      return safeBillingDate(prevMonth.year, prevMonth.month, billingDay);
    }
  }

  // จุดสิ้นสุดของรอบบิลปัจจุบัน (ไม่รวมวันนี้ ถ้าวันนี้ตรงกับวันตัดรอบ)
  static DateTime getCycleEnd(DateTime now, int billingDay) {
    final cutoffThisMonth = safeBillingDate(now.year, now.month, billingDay);
    if (now.day >= cutoffThisMonth.day) {
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      return safeBillingDate(nextMonth.year, nextMonth.month, billingDay);
    } else {
      return cutoffThisMonth;
    }
  }

  // จุดเริ่มต้นของรอบบิล "ก่อนหน้า" รอบที่ขึ้นต้นด้วย cycleStart ที่ให้มา
  // ใช้ตอนต้องปิดบิลของรอบก่อนหน้า (ดู dashboard_screen.dart -> compileBill)
  static DateTime getPreviousCycleStart(DateTime cycleStart, int billingDay) {
    final prevMonth = DateTime(cycleStart.year, cycleStart.month - 1, 1);
    return safeBillingDate(prevMonth.year, prevMonth.month, billingDay);
  }

  // เช็คว่า "เดือน/ปีที่ตั้งมิเตอร์ต้นรอบไว้" ยังตรงกับรอบบิลปัจจุบันไหม
  // แหล่งความจริงเดียวสำหรับเช็คนี้ — เดิมแต่ละหน้า (dashboard_screen.dart,
  // settings_start_meter.dart) ต่างคำนวณเองแยกกัน เสี่ยงแก้ไม่ครบทุกจุด
  static bool matchesCurrentCycle({
    required int billingMonth,
    required int billingYear,
    required int billingDay,
  }) {
    final expected = getCycleStart(DateTime.now(), billingDay);
    return billingMonth == expected.month && billingYear == expected.year;
  }

  // คำนวณจำนวนวันที่เหลือในรอบบิล
  static int getRemainingDays(DateTime now, int billingDay) {
    return getCycleEnd(now, billingDay).difference(now).inDays;
  }

  // คำนวณวันที่ผ่านมาในรอบบิล
  static int getDaysElapsed(DateTime now, int billingDay) {
    return now.difference(getCycleStart(now, billingDay)).inDays;
  }

  // ความยาวทั้งหมดของรอบบิลปัจจุบัน (หน่วย: วัน) — แหล่งความจริงเดียว
  //
  // ห้ามคำนวณด้วย getDaysElapsed(...) + getRemainingDays(...) แทน เพราะสอง
  // ค่านั้นต่างเทียบกับ DateTime.now() ที่มีเศษชั่วโมง/นาทีติดมาด้วย การปัด
  // เศษลง (floor ผ่าน .inDays) แยกกันคนละรอบ ทำให้ผลรวมคลาดจากความยาวรอบบิล
  // จริงได้ ±1 วัน ขึ้นกับเวลาที่เรียกฟังก์ชัน (เคยเป็นแบบนี้ใน
  // dashboard_screen.dart มาก่อน ทำให้ progress bar กับหน้าวิเคราะห์เห็นเลข
  // ไม่ตรงกันในวันเดียวกัน) — ที่นี่คำนวณตรงจากขอบเขตรอบบิล (cycleEnd -
  // cycleStart) ซึ่งทั้งคู่เป็น DateTime เที่ยงคืนไม่มีเศษเวลา จึงเสถียร
  static int getCycleLengthDays(DateTime now, int billingDay) {
    final startDate = getCycleStart(now, billingDay);
    final endDate = getCycleEnd(now, billingDay);
    return endDate.difference(startDate).inDays;
  }
}