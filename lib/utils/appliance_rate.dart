import '../models/bill_model.dart';

// อัตราค่าไฟต่อหน่วยที่ใช้ประมาณค่าไฟของอุปกรณ์ (หน้าอุปกรณ์และแท็บอุปกรณ์ใน
// หน้าวิเคราะห์ใช้ค่าเดียวกัน)
class ApplianceRate {
  final double perUnit; // บาท/หน่วย
  // บิลที่ใช้คำนวณอัตรา — null = ยังไม่มีบิลที่ใช้ได้ ใช้ค่าเฉลี่ยประมาณการแทน
  final BillModel? sourceBill;

  const ApplianceRate._(this.perUnit, this.sourceBill);

  // ค่าเฉลี่ยประมาณการ (รวม Ft และ VAT คร่าวๆ) เมื่อยังไม่มีบิลให้คำนวณ
  static const double defaultPerUnit = 4.5;

  // อัตราที่ได้นอกช่วงนี้ถือว่าข้อมูลบิลผิดปกติ (เช่น กรอกหน่วยผิด) ไม่นำมาใช้
  static const double _minPerUnit = 1;
  static const double _maxPerUnit = 15;

  static const ApplianceRate fallback = ApplianceRate._(defaultPerUnit, null);

  bool get isFromBill => sourceBill != null;

  // อัตราเฉลี่ยจริงของบ้านนี้ = ค่าไฟ ÷ หน่วยที่ใช้ ของบิลล่าสุดที่มีทั้งสองค่า
  // รวมขั้นบันได ค่า Ft VAT ค่าบริการ และสัดส่วน On/Off-Peak ของบ้านนั้นแล้ว
  // [bills] เรียงลำดับแบบใดก็ได้ — เลือกบิลเดือนล่าสุดเอง
  static ApplianceRate fromBills(List<BillModel> bills) {
    final usable = bills.where((b) {
      if (b.electricityUsed <= 0 || b.electricityCost <= 0) return false;
      final rate = b.electricityCost / b.electricityUsed;
      return rate >= _minPerUnit && rate <= _maxPerUnit;
    }).toList();
    if (usable.isEmpty) return fallback;
    final latest = usable.reduce((a, b) => a.yearMonth >= b.yearMonth ? a : b);
    return ApplianceRate._(
        latest.electricityCost / latest.electricityUsed, latest);
  }
}
