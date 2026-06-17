class UserModel {
  final String uid;
  final String name;
  final String email;
  final String area;
  final String meterType;
  final int billingDay;
  final String dailyCutoffTime;
  final double fixedCost;

  // หน่วยตั้งต้นของรอบบิลปัจจุบัน
  final double startElectricityValue; // หน่วยไฟต้นรอบ เช่น 14,009
  final double startWaterValue; // หน่วยน้ำต้นรอบ เช่น 148
  final int startBillingMonth; // เดือนที่ตั้งต้น เช่น 5
  final int startBillingYear; // ปีที่ตั้งต้น เช่น 2026

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.area = 'bangkok',
    this.meterType = 'normal',
    this.billingDay = 30,
    this.dailyCutoffTime = '00:00',
    this.fixedCost = 0,
    this.startElectricityValue = 0,
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
      billingDay: map['billingDay'] ?? 30,
      dailyCutoffTime: map['dailyCutoffTime'] ?? '00:00',
      fixedCost: (map['fixedCost'] ?? 0).toDouble(),
      startElectricityValue:
          (map['startElectricityValue'] ?? 0).toDouble(),
      startWaterValue: (map['startWaterValue'] ?? 0).toDouble(),
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
      'billingDay': billingDay,
      'dailyCutoffTime': dailyCutoffTime,
      'fixedCost': fixedCost,
      'startElectricityValue': startElectricityValue,
      'startWaterValue': startWaterValue,
      'startBillingMonth': startBillingMonth,
      'startBillingYear': startBillingYear,
    };
  }
}