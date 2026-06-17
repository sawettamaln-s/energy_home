class MeterLogModel {
  final String id;
  final String uid;
  final DateTime date;
  final double electricityValue; // หน่วยมิเตอร์ปัจจุบัน เช่น 14,052
  final double waterValue; // หน่วยมิเตอร์ปัจจุบัน เช่น 178
  final double electricityFromStart; // ใช้ไปจากต้นรอบ เช่น 43
  final double waterFromStart; // ใช้ไปจากต้นรอบ เช่น 30
  final double electricityIncrease; // เพิ่มจากครั้งล่าสุด เช่น 29
  final double waterIncrease; // เพิ่มจากครั้งล่าสุด เช่น 11
  final double electricityCost; // ค่าไฟประมาณการจากหน่วยรวมต้นรอบ
  final double waterCost; // ค่าน้ำประมาณการจากหน่วยรวมต้นรอบ
  final bool isMonthEnd; // เป็นการบันทึกสิ้นเดือนไหม

  MeterLogModel({
    required this.id,
    required this.uid,
    required this.date,
    required this.electricityValue,
    required this.waterValue,
    this.electricityFromStart = 0,
    this.waterFromStart = 0,
    this.electricityIncrease = 0,
    this.waterIncrease = 0,
    this.electricityCost = 0,
    this.waterCost = 0,
    this.isMonthEnd = false,
  });

  factory MeterLogModel.fromMap(Map<String, dynamic> map) {
    return MeterLogModel(
      id: map['id'] ?? '',
      uid: map['uid'] ?? '',
      date: DateTime.parse(map['date']),
      electricityValue: (map['electricityValue'] ?? 0).toDouble(),
      waterValue: (map['waterValue'] ?? 0).toDouble(),
      electricityFromStart: (map['electricityFromStart'] ?? 0).toDouble(),
      waterFromStart: (map['waterFromStart'] ?? 0).toDouble(),
      electricityIncrease: (map['electricityIncrease'] ?? 0).toDouble(),
      waterIncrease: (map['waterIncrease'] ?? 0).toDouble(),
      electricityCost: (map['electricityCost'] ?? 0).toDouble(),
      waterCost: (map['waterCost'] ?? 0).toDouble(),
      isMonthEnd: map['isMonthEnd'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'date': date.toIso8601String(),
      'electricityValue': electricityValue,
      'waterValue': waterValue,
      'electricityFromStart': electricityFromStart,
      'waterFromStart': waterFromStart,
      'electricityIncrease': electricityIncrease,
      'waterIncrease': waterIncrease,
      'electricityCost': electricityCost,
      'waterCost': waterCost,
      'isMonthEnd': isMonthEnd,
    };
  }
}