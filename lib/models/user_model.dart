class UserModel {
  final String uid;
  final String name;
  final String email;
  final String area;
  final String meterType; // 'normal' หรือ 'tou'
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

  // true = ผู้ใช้กรอกค่ามิเตอร์ตั้งต้นเรียบร้อยแล้ว (ไม่ว่าจะตอนสมัครหรือ
  // มาตั้งทีหลังที่หน้าตั้งค่า) / false = ตอนสมัครกด "ข้ามไปก่อน" ไว้ ยังไม่
  // เคยกรอกค่าจริง — ใช้แยกเคส "ข้าม" ออกจาก "กรอกเป็น 0 จริง" เพื่อกัน
  // ไม่ให้ Dashboard เอา 0 ไปคำนวณหน่วยที่ใช้แบบผิดๆตอนยังไม่ได้ตั้งค่า
  //
  // เดิม flag เดียวครอบทั้งไฟ+น้ำ แต่ตอนนี้อนุญาตให้กรอกแค่ยูทิลิตี้เดียว
  // ได้แล้ว (มีบิลแค่ใบเดียวในมือ) จึงต้องแยกเป็น 2 flag ย่อยด้านล่างด้วย
  // — เหลือ startMeterConfigured ไว้เป็น "เคยตั้งอย่างน้อย 1 อย่างไหม"
  // (= electricityStartConfigured || waterStartConfigured) เพื่อไม่ให้จุด
  // อื่นที่ยังอ้างอิง flag เดิมอยู่ (เช่น dashboard_screen.dart) พังทันที
  // รอไปแก้ logic การใช้งานจริงเป็นระดับยูทิลิตี้ทีหลัง
  final bool startMeterConfigured;
  final bool electricityStartConfigured;
  final bool waterStartConfigured;

  // true = ผู้ใช้เคยกดเลือกวันตัดรอบบิลเองจริงๆ แล้ว (ไม่ว่าจะตอนสมัครหรือ
  // มาตั้งทีหลังที่หน้าตั้งค่า) / false = ยังไม่เคยเลือกเอง กำลังใช้ค่า
  // default (billingDay = 30) อยู่เฉยๆ — เดิมไม่มี flag นี้เลย ทำให้หน้าหลัก
  // ไม่มีทางรู้ว่าค่า 30 ที่เห็นเป็น "ผู้ใช้ตั้งใจเลือกวันที่ 30 จริง" หรือ
  // "ยังไม่ได้ตั้งเลย" ก็เลยไม่มีตัวเตือนให้ไปตั้งค่าได้ — ใช้แพทเทิร์นเดียว
  // กับ startMeterConfigured ด้านบน
  final bool billingDayConfigured;

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
      dailyCutoffTime: map['dailyCutoffTime'] ?? '00:00',
      fixedCost: (map['fixedCost'] ?? 0).toDouble(),
      startElectricityValue: (map['startElectricityValue'] ?? 0).toDouble(),
      startWaterValue: (map['startWaterValue'] ?? 0).toDouble(),
      startPeakValue: (map['startPeakValue'] ?? 0).toDouble(),
      startOffPeakValue: (map['startOffPeakValue'] ?? 0).toDouble(),
      startBillingMonth: map['startBillingMonth'] ?? 0,
      startBillingYear: map['startBillingYear'] ?? 0,
      // บัญชีเก่าก่อนมี field นี้ (map ไม่มี key) ให้ default เป็น true เสมอ
      // เพราะบัญชีเก่าทุกบัญชีกรอกค่ามิเตอร์ตั้งต้นไว้แล้วตั้งแต่ตอนนั้น
      // (ฟีเจอร์ "ข้ามได้" เพิ่งมีทีหลัง)
      startMeterConfigured: map['startMeterConfigured'] ?? true,
      // บัญชีเก่าก่อนมี flag แยกยูทิลิตี้ (ยังไม่มี key นี้ใน map) ให้ fallback
      // ไปใช้ค่า startMeterConfigured เดิม (ครอบทั้งไฟ+น้ำเหมือนพฤติกรรมเดิม
      // ก่อนแยก) จนกว่าผู้ใช้จะมาตั้งค่าใหม่ผ่านฟอร์มที่แยกยูทิลิตี้แล้ว
      electricityStartConfigured: map['electricityStartConfigured'] ??
          map['startMeterConfigured'] ??
          true,
      waterStartConfigured:
          map['waterStartConfigured'] ?? map['startMeterConfigured'] ?? true,
      // บัญชีเก่าก่อนมี field นี้ (map ไม่มี key) ให้ default เป็น true เสมอ
      // เพราะตอนนั้นเซตอัพยังบังคับให้เลือกวันตัดรอบบิลอยู่ (ฟีเจอร์ "ข้าม
      // ได้" เพิ่งมาตัดขั้นนี้ออกทีหลัง) จึงถือว่าบัญชีเก่าทุกบัญชีเลือกไปแล้ว
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
      'dailyCutoffTime': dailyCutoffTime,
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