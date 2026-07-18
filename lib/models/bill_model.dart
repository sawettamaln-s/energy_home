class BillModel {
  final String id;
  final String uid;
  final int year;
  final int month;
  final double electricityUsed; // หน่วยไฟฟ้าที่ใช้รวมทั้งเดือน
  // TOU เท่านั้น: แยกหน่วยที่ใช้เป็น On-Peak/Off-Peak (ผลรวมของสองค่านี้ควร
  // เท่ากับ electricityUsed ด้านบนเสมอ) — เก็บแยกไว้ด้วยเพื่อให้หน้าประวัติ
  // บิลย้อนหลังโชว์ค่าที่กรอกจริงแยกประเภทได้ ไม่ใช่แค่ยอดรวมเดียว บิลเก่า
  // ก่อนมีฟิลด์นี้ (หรือมิเตอร์ปกติ) จะเป็น 0 ทั้งคู่ตามค่า default
  final double electricityPeakUsed;
  final double electricityOffPeakUsed;
  final double waterUsed; // หน่วยน้ำที่ใช้รวมทั้งเดือน
  final double electricityCost; // ค่าไฟรวมทั้งเดือน
  final double waterCost; // ค่าน้ำรวมทั้งเดือน
  final double fixedCost; // ค่าใช้จ่ายคงที่
  final double totalCost; // ยอดรวมทั้งหมด
  final double forecastElectricity; // พยากรณ์ค่าไฟสิ้นเดือน (Moving Average)
  final double forecastWater; // พยากรณ์ค่าน้ำสิ้นเดือน (Moving Average)
  final double forecastTotal; // พยากรณ์ยอดรวมสิ้นเดือน
  final String source; // 'compiled' = ระบบสรุปจาก log อัตโนมัติ, 'imported' = กรอกย้อนหลังเอง

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
    this.forecastElectricity = 0,
    this.forecastWater = 0,
    this.forecastTotal = 0,
    this.source = 'compiled',
  });

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
      forecastElectricity: (map['forecastElectricity'] ?? 0).toDouble(),
      forecastWater: (map['forecastWater'] ?? 0).toDouble(),
      forecastTotal: (map['forecastTotal'] ?? 0).toDouble(),
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
      'forecastElectricity': forecastElectricity,
      'forecastWater': forecastWater,
      'forecastTotal': forecastTotal,
      'source': source,
    };
  }
}