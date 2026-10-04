part of 'settings_screen.dart';

// =====================================================================
// คำนวณค่าใช้จ่ายอัตโนมัติขณะพิมพ์หน่วย/เลขมิเตอร์ — ใช้ร่วมกันระหว่างฟอร์ม
// เลขมิเตอร์ต้นรอบ (settings_start_meter.dart) และฟอร์มบิลเดือนเก่า
// (settings_bill_form.dart) แต่ละฟอร์มหา "หน่วย" เอง แล้วให้ตัวนี้คิดเงิน
//
// หน่วงเวลา 400 ms หลังพิมพ์ตัวสุดท้ายก่อนคำนวณ กันเรียก getFtRate() (อ่าน
// Firestore) ทุกตัวอักษร ช่องค่าใช้จ่ายไม่ถูกล็อก ผู้ใช้แก้ค่าที่คำนวณได้เอง
// =====================================================================
class _CostAutofill {
  static const _delay = Duration(milliseconds: 400);
  Timer? _electricity;
  Timer? _water;

  void scheduleElectricity(void Function() run) {
    _electricity?.cancel();
    _electricity = Timer(_delay, run);
  }

  void scheduleWater(void Function() run) {
    _water?.cancel();
    _water = Timer(_delay, run);
  }

  void dispose() {
    _electricity?.cancel();
    _water?.cancel();
  }

  // ข้อความค่าไฟสำหรับช่องค่าใช้จ่าย (ทศนิยม 2 ตำแหน่ง) ตามประเภทมิเตอร์และ
  // ประเภทอัตราของผู้ใช้ — ยังไม่มีหน่วยเลย = '0.00'
  static Future<String> electricityText({
    required UserModel user,
    required bool isTou,
    double units = 0,
    double peakUnits = 0,
    double offPeakUnits = 0,
  }) async {
    if (units <= 0 && peakUnits <= 0 && offPeakUnits <= 0) return '0.00';
    final cost = await EnergyCalculator.calculateElectricityByType(
      units: units,
      meterType: isTou ? 'tou' : 'normal',
      area: user.area,
      peakUnits: peakUnits,
      offPeakUnits: offPeakUnits,
      tariff: user.electricityTariff,
    );
    return cost.toStringAsFixed(2);
  }

  // เหมือน electricityText แต่ฝั่งน้ำ (calculateWater เป็น sync)
  static String waterText(UserModel user, double units) {
    if (units <= 0) return '0.00';
    return EnergyCalculator.calculateWater(units, user.area).toStringAsFixed(2);
  }
}
