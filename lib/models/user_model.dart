class UserModel {
  final String uid;
  final String name;
  final String email;
  final String area; // 'bangkok' = เขต MEA, 'province' = เขต PEA
  final String meterType; // 'normal' หรือ 'tou'

  // เดิม: billingDay ตัวเดียวใช้ร่วมกันทั้งไฟและน้ำ (ความจริงวันตัดรอบมักไม่ตรงกัน)
  // คงไว้เพื่อ backward compat กับ document เก่าใน Firestore ที่ยังไม่ผ่าน migration
  // ห้ามใช้ค่านี้ในโค้ดใหม่ — ใช้ electricityBillingDay / waterBillingDay แทน
  final int billingDay;

  // วันตัดรอบบิลแยกต่อยูทิลิตี้ (ค่าจริงที่โค้ดใหม่ทั้งหมดควรใช้)
  final int electricityBillingDay;
  final int waterBillingDay;

  final double fixedCost;

  // หน่วยตั้งต้นของรอบบิลปัจจุบัน
  final double startElectricityValue; // หน่วยไฟต้นรอบ เช่น 14,009
  final double startWaterValue; // หน่วยน้ำต้นรอบ เช่น 148
  final double startPeakValue; // หน่วยตั้งต้น On-Peak (เฉพาะ TOU)
  final double startOffPeakValue; // หน่วยตั้งต้น Off-Peak (เฉพาะ TOU)

  // เดิม: เดือน/ปีที่ตั้งต้น ใช้ร่วมกันทั้งไฟและน้ำ — คงไว้เพื่อ backward compat เท่านั้น
  final int startBillingMonth; // เดือนที่ตั้งต้น เช่น 5
  final int startBillingYear; // ปีที่ตั้งต้น เช่น 2026

  // เดือน/ปีที่ตั้งต้นแยกต่อยูทิลิตี้ (เพราะวันตัดรอบแยกกัน เดือนตั้งต้นจึงอาจไม่ตรงกัน)
  final int electricityStartBillingMonth;
  final int electricityStartBillingYear;
  final int waterStartBillingMonth;
  final int waterStartBillingYear;

  // true = ตั้งค่ามิเตอร์ต้นรอบแล้ว, false = ตอนสมัครกด "ข้ามไปก่อน"
  // (กันไม่ให้ Dashboard เอา 0 ไปคำนวณผิดตอนยังไม่ได้ตั้งค่า)
  // startMeterConfigured = ตั้งไปแล้วอย่างน้อย 1 ยูทิลิตี้ (electricity || water)
  // ส่วน 2 ตัวล่างคือ flag แยกรายยูทิลิตี้ เพราะตอนนี้ตั้งแค่ไฟหรือน้ำอย่างเดียวก็ได้
  final bool startMeterConfigured;
  final bool electricityStartConfigured;
  final bool waterStartConfigured;

  // เดิม: billingDayConfigured ตัวเดียวใช้ร่วมกัน คงไว้เพื่อ backward compat
  final bool billingDayConfigured;

  // true = ผู้ใช้เคยเลือกวันตัดรอบบิลเองของยูทิลิตี้นั้น, false = ยังใช้ค่า default
  // แยกต่อยูทิลิตี้เช่นเดียวกับ billingDay
  final bool electricityBillingDayConfigured;
  final bool waterBillingDayConfigured;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.area = 'bangkok',
    this.meterType = 'normal',
    int billingDay = 30,
    int? electricityBillingDay,
    int? waterBillingDay,
    this.fixedCost = 0,
    this.startElectricityValue = 0,
    this.startPeakValue = 0,
    this.startOffPeakValue = 0,
    this.startWaterValue = 0,
    int startBillingMonth = 0,
    int startBillingYear = 0,
    int? electricityStartBillingMonth,
    int? electricityStartBillingYear,
    int? waterStartBillingMonth,
    int? waterStartBillingYear,
    this.startMeterConfigured = true,
    this.electricityStartConfigured = true,
    this.waterStartConfigured = true,
    bool billingDayConfigured = true,
    bool? electricityBillingDayConfigured,
    bool? waterBillingDayConfigured,
  })  : billingDay = billingDay,
        electricityBillingDay = electricityBillingDay ?? billingDay,
        waterBillingDay = waterBillingDay ?? billingDay,
        startBillingMonth = startBillingMonth,
        startBillingYear = startBillingYear,
        electricityStartBillingMonth =
            electricityStartBillingMonth ?? startBillingMonth,
        electricityStartBillingYear =
            electricityStartBillingYear ?? startBillingYear,
        waterStartBillingMonth = waterStartBillingMonth ?? startBillingMonth,
        waterStartBillingYear = waterStartBillingYear ?? startBillingYear,
        billingDayConfigured = billingDayConfigured,
        electricityBillingDayConfigured =
            electricityBillingDayConfigured ?? billingDayConfigured,
        waterBillingDayConfigured =
            waterBillingDayConfigured ?? billingDayConfigured;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final int legacyBillingDay = map['billingDay'] ?? 30;
    final int legacyStartMonth = map['startBillingMonth'] ?? 0;
    final int legacyStartYear = map['startBillingYear'] ?? 0;
    final bool legacyBillingDayConfigured =
        map['billingDayConfigured'] ?? true;

    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      area: map['area'] ?? 'bangkok',
      meterType: map['meterType'] ?? 'normal',
      billingDay: legacyBillingDay,
      // บัญชีเก่าไม่มี key แยกยูทิลิตี้ -> fallback ไปใช้ billingDay เดิม
      electricityBillingDay: map['electricityBillingDay'] ?? legacyBillingDay,
      waterBillingDay: map['waterBillingDay'] ?? legacyBillingDay,
      fixedCost: (map['fixedCost'] ?? 0).toDouble(),
      startElectricityValue: (map['startElectricityValue'] ?? 0).toDouble(),
      startWaterValue: (map['startWaterValue'] ?? 0).toDouble(),
      startPeakValue: (map['startPeakValue'] ?? 0).toDouble(),
      startOffPeakValue: (map['startOffPeakValue'] ?? 0).toDouble(),
      startBillingMonth: legacyStartMonth,
      startBillingYear: legacyStartYear,
      electricityStartBillingMonth:
          map['electricityStartBillingMonth'] ?? legacyStartMonth,
      electricityStartBillingYear:
          map['electricityStartBillingYear'] ?? legacyStartYear,
      waterStartBillingMonth:
          map['waterStartBillingMonth'] ?? legacyStartMonth,
      waterStartBillingYear:
          map['waterStartBillingYear'] ?? legacyStartYear,
      // บัญชีเก่าไม่มี key นี้ -> default true (ตอนนั้นบังคับกรอกค่าตั้งต้นอยู่แล้ว)
      startMeterConfigured: map['startMeterConfigured'] ?? true,
      // บัญชีเก่าไม่มี flag แยกยูทิลิตี้ -> fallback ไปใช้ startMeterConfigured เดิม
      electricityStartConfigured: map['electricityStartConfigured'] ??
          map['startMeterConfigured'] ??
          true,
      waterStartConfigured:
          map['waterStartConfigured'] ?? map['startMeterConfigured'] ?? true,
      // บัญชีเก่าไม่มี key นี้ -> default true (ตอนนั้นบังคับเลือกวันตัดรอบอยู่แล้ว)
      billingDayConfigured: legacyBillingDayConfigured,
      // บัญชีเก่าไม่มี flag แยกยูทิลิตี้ -> fallback ไปใช้ billingDayConfigured เดิม
      electricityBillingDayConfigured:
          map['electricityBillingDayConfigured'] ??
              legacyBillingDayConfigured,
      waterBillingDayConfigured:
          map['waterBillingDayConfigured'] ?? legacyBillingDayConfigured,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'area': area,
      'meterType': meterType,
      // เก็บ key เดิมไว้คู่กับของใหม่ระหว่าง migrate เผื่อมีเวอร์ชันแอปเก่ายังอ่าน key นี้อยู่
      'billingDay': billingDay,
      'electricityBillingDay': electricityBillingDay,
      'waterBillingDay': waterBillingDay,
      'fixedCost': fixedCost,
      'startElectricityValue': startElectricityValue,
      'startWaterValue': startWaterValue,
      'startPeakValue': startPeakValue,
      'startOffPeakValue': startOffPeakValue,
      'startBillingMonth': startBillingMonth,
      'startBillingYear': startBillingYear,
      'electricityStartBillingMonth': electricityStartBillingMonth,
      'electricityStartBillingYear': electricityStartBillingYear,
      'waterStartBillingMonth': waterStartBillingMonth,
      'waterStartBillingYear': waterStartBillingYear,
      'startMeterConfigured': startMeterConfigured,
      'electricityStartConfigured': electricityStartConfigured,
      'waterStartConfigured': waterStartConfigured,
      'billingDayConfigured': billingDayConfigured,
      'electricityBillingDayConfigured': electricityBillingDayConfigured,
      'waterBillingDayConfigured': waterBillingDayConfigured,
    };
  }
}