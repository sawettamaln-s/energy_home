class UserModel {
  final String uid;
  final String name;
  final String email;
  final String area;
  final String meterType; // 'normal' หรือ 'tou'
  final String meterSize; // '5a' หรือ '15a' - ใช้เฉพาะ MEA (กรุงเทพ)
  final int billingDay;
  final String dailyCutoffTime;
  final double fixedCost;

  // หน่วยตั้งต้นของรอบบิลปัจจุบัน
  final double startElectricityValue; // หน่วยไฟต้นรอบ เช่น 14,009
  final double startWaterValue; // หน่วยน้ำต้นรอบ เช่น 148
  final double startPeakValue; // หน่วยตั้งต้น On-Peak (เฉพาะ TOU)
  final double startOffPeakValue; // หน่วยตั้งต้น Off-Peak (เฉพาะ TOU)
  final int startBillingMonth; // เดือนที่ตั้งต้น เช่น 5
  final int startBillingYear; // ปีที่ตั้งต้น เช่น 2026

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.area = 'bangkok',
    this.meterType = 'normal',
    this.meterSize = '15a',
    this.billingDay = 30,
    this.dailyCutoffTime = '00:00',
    this.fixedCost = 0,
    this.startElectricityValue = 0,
    this.startPeakValue = 0,
    this.startOffPeakValue = 0,
    this.startWaterValue = 0,
    this.startBillingMonth = 0,
    this.startBillingYear = 0,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      area: map['area'] ?? 'bangkok',
      meterType: map['meterType'] ?? 'normal',
      meterSize: map['meterSize'] ?? '15a',
      billingDay: map['billingDay'] ?? 30,
      dailyCutoffTime: map['dailyCutoffTime'] ?? '00:00',
      fixedCost: (map['fixedCost'] ?? 0).toDouble(),
      startElectricityValue: (map['startElectricityValue'] ?? 0).toDouble(),
      startWaterValue: (map['startWaterValue'] ?? 0).toDouble(),
      startPeakValue: (map['startPeakValue'] ?? 0).toDouble(),
      startOffPeakValue: (map['startOffPeakValue'] ?? 0).toDouble(),
      startBillingMonth: map['startBillingMonth'] ?? 0,
      startBillingYear: map['startBillingYear'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'area': area,
      'meterType': meterType,
      'meterSize': meterSize,
      'billingDay': billingDay,
      'dailyCutoffTime': dailyCutoffTime,
      'fixedCost': fixedCost,
      'startElectricityValue': startElectricityValue,
      'startWaterValue': startWaterValue,
      'startPeakValue': startPeakValue,
      'startOffPeakValue': startOffPeakValue,
      'startBillingMonth': startBillingMonth,
      'startBillingYear': startBillingYear,
    };
  }
}
