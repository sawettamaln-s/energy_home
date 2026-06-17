class BillModel {
  final String id;
  final String uid;
  final int year;
  final int month;
  final double electricityUsed; // หน่วยไฟฟ้าที่ใช้รวมทั้งเดือน
  final double waterUsed; // หน่วยน้ำที่ใช้รวมทั้งเดือน
  final double electricityCost; // ค่าไฟรวมทั้งเดือน
  final double waterCost; // ค่าน้ำรวมทั้งเดือน
  final double fixedCost; // ค่าใช้จ่ายคงที่
  final double totalCost; // ยอดรวมทั้งหมด
  final double forecastElectricity; // พยากรณ์ค่าไฟสิ้นเดือน (Moving Average)
  final double forecastWater; // พยากรณ์ค่าน้ำสิ้นเดือน (Moving Average)
  final double forecastTotal; // พยากรณ์ยอดรวมสิ้นเดือน
  final bool isComplete; // ครบรอบบิลแล้วหรือยัง

  BillModel({
    required this.id,
    required this.uid,
    required this.year,
    required this.month,
    this.electricityUsed = 0,
    this.waterUsed = 0,
    this.electricityCost = 0,
    this.waterCost = 0,
    this.fixedCost = 0,
    this.totalCost = 0,
    this.forecastElectricity = 0,
    this.forecastWater = 0,
    this.forecastTotal = 0,
    this.isComplete = false,
  });

  // แปลงจาก Firestore เป็น Model
  factory BillModel.fromMap(Map<String, dynamic> map) {
    return BillModel(
      id: map['id'] ?? '',
      uid: map['uid'] ?? '',
      year: map['year'] ?? 0,
      month: map['month'] ?? 0,
      electricityUsed: (map['electricityUsed'] ?? 0).toDouble(),
      waterUsed: (map['waterUsed'] ?? 0).toDouble(),
      electricityCost: (map['electricityCost'] ?? 0).toDouble(),
      waterCost: (map['waterCost'] ?? 0).toDouble(),
      fixedCost: (map['fixedCost'] ?? 0).toDouble(),
      totalCost: (map['totalCost'] ?? 0).toDouble(),
      forecastElectricity: (map['forecastElectricity'] ?? 0).toDouble(),
      forecastWater: (map['forecastWater'] ?? 0).toDouble(),
      forecastTotal: (map['forecastTotal'] ?? 0).toDouble(),
      isComplete: map['isComplete'] ?? false,
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
      'waterUsed': waterUsed,
      'electricityCost': electricityCost,
      'waterCost': waterCost,
      'fixedCost': fixedCost,
      'totalCost': totalCost,
      'forecastElectricity': forecastElectricity,
      'forecastWater': forecastWater,
      'forecastTotal': forecastTotal,
      'isComplete': isComplete,
    };
  }
}