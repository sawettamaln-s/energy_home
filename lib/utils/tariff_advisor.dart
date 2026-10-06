import '../models/bill_model.dart';
import 'calculator.dart';

// คำแนะนำให้ตรวจประเภทอัตราค่าไฟ ตามกติกาการจัดประเภทของการไฟฟ้า:
// มิเตอร์ไม่เกิน 5 แอมแปร์ที่ใช้ไม่เกิน 150 หน่วยติดต่อกัน 3 เดือน เดือนถัดไป
// เป็นประเภทใช้ไม่เกิน 150 หน่วย และถ้าใช้เกิน 150 หน่วยติดต่อกัน 3 เดือน เดือน
// ถัดไปกลับเป็นประเภทใช้เกิน 150 หน่วย — แอปไม่รู้ขนาดมิเตอร์ จึงแค่แนะนำให้
// ผู้ใช้ตรวจใบแจ้งหนี้ ไม่เปลี่ยนเอง
class TariffHint {
  final String suggestedTariff; // EnergyCalculator.tariffSmall/tariffStandard
  final List<BillModel> bills; // บิล 3 เดือนติดกันที่ใช้ตัดสิน เรียงเก่า -> ใหม่

  const TariffHint(this.suggestedTariff, this.bills);

  BillModel get latest => bills.last;
}

class TariffAdvisor {
  static const double threshold = 150; // หน่วย/เดือน
  static const int consecutiveMonths = 3;

  // คืนคำแนะนำเมื่อบิล 3 เดือนล่าสุด (ติดกันตามเดือนจริง และมีหน่วยไฟทุกใบ)
  // เข้าเงื่อนไขเปลี่ยนประเภท ไม่เข้าเงื่อนไข/ข้อมูลไม่พอ/มิเตอร์ TOU คืน null
  // นับเฉพาะบิลที่หน่วยมาจากเลขมิเตอร์จริง (ใบแจ้งหนี้/เลขต้นรอบ/บิลที่กรอกเอง)
  // ไม่นับบิล 'compiled' ซึ่งประมาณหน่วยถึงวันตัดรอบ — หน่วยใกล้ 150 ตัวเลข
  // ประมาณอาจพาให้แนะนำผิดฝั่ง
  static TariffHint? check({
    required List<BillModel> bills,
    required String currentTariff,
    required String meterType,
  }) {
    if (meterType == 'tou' || bills.isEmpty) return null;
    final sorted = bills.where((b) => b.source != 'compiled').toList()
      ..sort((a, b) => a.yearMonth.compareTo(b.yearMonth));
    if (sorted.length < consecutiveMonths) return null;
    final recent = sorted.sublist(sorted.length - consecutiveMonths);

    for (var i = 1; i < recent.length; i++) {
      final prev = recent[i - 1];
      final cur = recent[i];
      final gap = (cur.year * 12 + cur.month) - (prev.year * 12 + prev.month);
      if (gap != 1) return null;
    }
    if (recent.any((b) => b.electricityUsed <= 0)) return null;

    final allLow = recent.every((b) => b.electricityUsed <= threshold);
    final allHigh = recent.every((b) => b.electricityUsed > threshold);
    if (currentTariff != EnergyCalculator.tariffSmall && allLow) {
      return TariffHint(EnergyCalculator.tariffSmall, recent);
    }
    if (currentTariff == EnergyCalculator.tariffSmall && allHigh) {
      return TariffHint(EnergyCalculator.tariffStandard, recent);
    }
    return null;
  }
}
