// ประวัติเลขมิเตอร์ต้นรอบ — 1 รายการต่อ 1 รอบบิล (แก้ไขรอบปัจจุบันจะเขียนทับ
// รายการเดิม ไม่สร้างใหม่) ใช้ย้อนดูเลขต้นรอบของแต่ละรอบ และเป็นฐานคำนวณ
// หน่วยที่ใช้ของรอบถัดไป
// ค่าไฟฟ้า/น้ำที่เป็น 0 = รอบนั้นไม่ได้ตั้งค่าฝั่งนั้น
class StartMeterRecordModel {
  final String id;
  final String uid;
  final double electricityValue;
  final double waterValue;
  final double peakValue; // เฉพาะมิเตอร์ TOU
  final double offPeakValue; // เฉพาะมิเตอร์ TOU
  // เดือนของใบแจ้งหนี้ที่อ่านเลขนี้ (= เดือนที่รอบบิลใหม่เริ่มนับจากเลขนี้)
  final int billingMonth;
  final int billingYear;
  final DateTime recordedAt; // เวลาที่กดบันทึก (ไม่ใช่เดือนของรอบบิล)

  StartMeterRecordModel({
    required this.id,
    required this.uid,
    required this.electricityValue,
    required this.waterValue,
    this.peakValue = 0,
    this.offPeakValue = 0,
    required this.billingMonth,
    required this.billingYear,
    required this.recordedAt,
  });

  factory StartMeterRecordModel.fromMap(Map<String, dynamic> map) {
    return StartMeterRecordModel(
      id: map['id'] ?? '',
      uid: map['uid'] ?? '',
      electricityValue: (map['electricityValue'] ?? 0).toDouble(),
      waterValue: (map['waterValue'] ?? 0).toDouble(),
      peakValue: (map['peakValue'] ?? 0).toDouble(),
      offPeakValue: (map['offPeakValue'] ?? 0).toDouble(),
      billingMonth: map['billingMonth'] ?? 0,
      billingYear: map['billingYear'] ?? 0,
      recordedAt: map['recordedAt'] != null
          ? DateTime.parse(map['recordedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'electricityValue': electricityValue,
      'waterValue': waterValue,
      'peakValue': peakValue,
      'offPeakValue': offPeakValue,
      'billingMonth': billingMonth,
      'billingYear': billingYear,
      'recordedAt': recordedAt.toIso8601String(),
    };
  }
}