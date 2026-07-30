class UserModel {
  final String uid;
  final String name;
  final String email;
  final String area; // 'bangkok' = เขต MEA, 'province' = เขต PEA
  final String meterType; // 'normal' หรือ 'tou'
  final int billingDay;
  final double fixedCost;

  // หน่วยตั้งต้นของรอบบิลปัจจุบัน
  final double startElectricityValue; // หน่วยไฟต้นรอบ เช่น 14,009
  final double startWaterValue; // หน่วยน้ำต้นรอบ เช่น 148
  final double startPeakValue; // หน่วยตั้งต้น On-Peak (เฉพาะ TOU)
  final double startOffPeakValue; // หน่วยตั้งต้น Off-Peak (เฉพาะ TOU)
  final int startBillingMonth; // เดือนที่ตั้งต้น เช่น 5
  final int startBillingYear; // ปีที่ตั้งต้น เช่น 2026

  // true = ตั้งค่ามิเตอร์ต้นรอบแล้ว, false = ตอนสมัครกด "ข้ามไปก่อน"
  // (กันไม่ให้ Dashboard เอา 0 ไปคำนวณผิดตอนยังไม่ได้ตั้งค่า)
  // startMeterConfigured = ตั้งไปแล้วอย่างน้อย 1 ยูทิลิตี้ (electricity || water)
  // ส่วน 2 ตัวล่างคือ flag แยกรายยูทิลิตี้ เพราะตอนนี้ตั้งแค่ไฟหรือน้ำอย่างเดียวก็ได้
  final bool startMeterConfigured;
  final bool electricityStartConfigured;
  final bool waterStartConfigured;

  // true = ผู้ใช้เคยเลือกวันตัดรอบบิลเอง, false = ยังใช้ค่า default (billingDay = 30)
  // อยู่เฉยๆ (ใช้แยกกรณี "ตั้งใจเลือก 30" กับ "ยังไม่ได้ตั้ง" เพื่อโชว์ตัวเตือน)
  final bool billingDayConfigured;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.area = 'bangkok',
    this.meterType = 'normal',
    this.billingDay = 30,
    this.fixedCost = 0,
    this.startElectricityValue = 0,
    this.startPeakValue = 0,
    this.startOffPeakValue = 0,
    this.startWaterValue = 0,
    this.startBillingMonth = 0,
    this.startBillingYear = 0,
    this.startMeterConfigured = true,
    this.electricityStartConfigured = true,
    this.waterStartConfigured = true,
    this.billingDayConfigured = true,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      area: map['area'] ?? 'bangkok',
      meterType: map['meterType'] ?? 'normal',
      billingDay: map['billingDay'] ?? 30,
      fixedCost: (map['fixedCost'] ?? 0).toDouble(),
      startElectricityValue: (map['startElectricityValue'] ?? 0).toDouble(),
      startWaterValue: (map['startWaterValue'] ?? 0).toDouble(),
      startPeakValue: (map['startPeakValue'] ?? 0).toDouble(),
      startOffPeakValue: (map['startOffPeakValue'] ?? 0).toDouble(),
      startBillingMonth: map['startBillingMonth'] ?? 0,
      startBillingYear: map['startBillingYear'] ?? 0,
      // บัญชีเก่าไม่มี key นี้ -> default true (ตอนนั้นบังคับกรอกค่าตั้งต้นอยู่แล้ว)
      startMeterConfigured: map['startMeterConfigured'] ?? true,
      // บัญชีเก่าไม่มี flag แยกยูทิลิตี้ -> fallback ไปใช้ startMeterConfigured เดิม
      electricityStartConfigured: map['electricityStartConfigured'] ??
          map['startMeterConfigured'] ??
          true,
      waterStartConfigured:
          map['waterStartConfigured'] ?? map['startMeterConfigured'] ?? true,
      // บัญชีเก่าไม่มี key นี้ -> default true (ตอนนั้นบังคับเลือกวันตัดรอบอยู่แล้ว)
      billingDayConfigured: map['billingDayConfigured'] ?? true,
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
      'fixedCost': fixedCost,
      'startElectricityValue': startElectricityValue,
      'startWaterValue': startWaterValue,
      'startPeakValue': startPeakValue,
      'startOffPeakValue': startOffPeakValue,
      'startBillingMonth': startBillingMonth,
      'startBillingYear': startBillingYear,
      'startMeterConfigured': startMeterConfigured,
      'electricityStartConfigured': electricityStartConfigured,
      'waterStartConfigured': waterStartConfigured,
      'billingDayConfigured': billingDayConfigured,
    };
  }
}