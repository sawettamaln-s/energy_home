class WaterLogModel {
  final String id;
  final String uid;
  final DateTime date;
  final double meterValue; // หน่วยมิเตอร์ปัจจุบัน เช่น 178
  final double usedFromStart; // ใช้ไปจากต้นรอบ เช่น 30
  final double usedFromLast; // เพิ่มจากครั้งล่าสุด เช่น 11
  final double cost; // ค่าน้ำประมาณการ
  final bool isMonthEnd; // บันทึกสิ้นเดือนไหม

  WaterLogModel({
    required this.id,
    required this.uid,
    required this.date,
    required this.meterValue,
    this.usedFromStart = 0,
    this.usedFromLast = 0,
    this.cost = 0,
    this.isMonthEnd = false,
  });

  factory WaterLogModel.fromMap(Map<String, dynamic> map) {
    return WaterLogModel(
      id: map['id'] ?? '',
      uid: map['uid'] ?? '',
      date: DateTime.parse(map['date']),
      meterValue: (map['meterValue'] ?? 0).toDouble(),
      usedFromStart: (map['usedFromStart'] ?? 0).toDouble(),
      usedFromLast: (map['usedFromLast'] ?? 0).toDouble(),
      cost: (map['cost'] ?? 0).toDouble(),
      isMonthEnd: map['isMonthEnd'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'date': date.toIso8601String(),
      'meterValue': meterValue,
      'usedFromStart': usedFromStart,
      'usedFromLast': usedFromLast,
      'cost': cost,
      'isMonthEnd': isMonthEnd,
    };
  }
}