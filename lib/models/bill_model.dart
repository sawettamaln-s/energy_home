/// บิล 1 เดือน — year/month คือเดือนของใบแจ้งหนี้ (วันตัดรอบที่ปิดรอบนั้น)
/// ไม่ใช่เดือนที่รอบเริ่ม
class BillModel {
  final String id;
  final String uid;
  final int year;
  final int month;
  final double electricityUsed; // หน่วยไฟฟ้าที่ใช้รวมทั้งเดือน
  final double electricityPeakUsed; // หน่วยไฟฟ้าช่วง On-Peak (เฉพาะมิเตอร์ TOU)
  final double electricityOffPeakUsed; // หน่วยไฟฟ้าช่วง Off-Peak (เฉพาะมิเตอร์ TOU)
  final double waterUsed; // หน่วยน้ำที่ใช้รวมทั้งเดือน
  final double electricityCost; // ค่าไฟรวมทั้งเดือน
  final double waterCost; // ค่าน้ำรวมทั้งเดือน
  final double fixedCost; // ค่าใช้จ่ายคงที่
  final double totalCost; // ยอดรวมทั้งหมด
  // ที่มาของบิล: 'compiled' = ระบบสรุปจาก log รายวันตอนปิดรอบ,
  // 'imported' = ผู้ใช้กรอกย้อนหลังเองที่หน้าประวัติบิล,
  // 'startMeter' = สร้างพร้อมการตั้งเลขมิเตอร์ต้นรอบ (แก้/ลบได้จากหน้านั้นเท่านั้น)
  final String source;

  // ฟิลด์ derived สำหรับ query หา "บิลล่าสุด" ด้วย orderBy ฟิลด์เดียว
  // (year*100+month) แทนที่จะต้อง orderBy 2 ฟิลด์ (year, month) ซึ่ง
  // Firestore ต้องใช้ composite index — คำนวณเองในตัว constructor เสมอ
  // ผู้เรียกไม่ต้องส่งเข้ามา กันลืมและกันค่าไม่ตรงกับ year/month จริง
  final int yearMonth;

  BillModel({
    required this.id,
    required this.uid,
    required this.year,
    required this.month,
    this.electricityUsed = 0,
    this.electricityPeakUsed = 0,
    this.electricityOffPeakUsed = 0,
    this.waterUsed = 0,
    this.electricityCost = 0,
    this.waterCost = 0,
    this.fixedCost = 0,
    this.totalCost = 0,
    this.source = 'compiled',
  }) : yearMonth = year * 100 + month;

  // แปลงจาก Firestore เป็น Model
  factory BillModel.fromMap(Map<String, dynamic> map) {
    return BillModel(
      id: map['id'] ?? '',
      uid: map['uid'] ?? '',
      year: map['year'] ?? 0,
      month: map['month'] ?? 0,
      electricityUsed: (map['electricityUsed'] ?? 0).toDouble(),
      electricityPeakUsed: (map['electricityPeakUsed'] ?? 0).toDouble(),
      electricityOffPeakUsed: (map['electricityOffPeakUsed'] ?? 0).toDouble(),
      waterUsed: (map['waterUsed'] ?? 0).toDouble(),
      electricityCost: (map['electricityCost'] ?? 0).toDouble(),
      waterCost: (map['waterCost'] ?? 0).toDouble(),
      fixedCost: (map['fixedCost'] ?? 0).toDouble(),
      totalCost: (map['totalCost'] ?? 0).toDouble(),
      source: map['source'] ?? 'compiled',
    );
  }

  // แปลงจาก Model เป็น Map เพื่อบันทึกลง Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'year': year,
      'month': month,
      'electricityUsed': electricityUsed,
      'electricityPeakUsed': electricityPeakUsed,
      'electricityOffPeakUsed': electricityOffPeakUsed,
      'waterUsed': waterUsed,
      'electricityCost': electricityCost,
      'waterCost': waterCost,
      'fixedCost': fixedCost,
      'totalCost': totalCost,
      'source': source,
      'yearMonth': yearMonth,
    };
  }
}