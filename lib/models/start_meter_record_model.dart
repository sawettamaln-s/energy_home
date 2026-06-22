// บันทึกประวัติการตั้ง/แก้ไขค่ามิเตอร์ต้นรอบ
// ทุกครั้งที่ผู้ใช้บันทึกค่ามิเตอร์ต้นรอบใหม่ (ไม่ว่าจะตั้งครั้งแรกหรือแก้ไขของเดิม)
// จะถูกเก็บเป็นรายการในนี้ เพื่อให้ย้อนดูได้ว่าค่าก่อนหน้าคืออะไร ตั้งไว้ตอนไหน
class StartMeterRecordModel {
  final String id;
  final String uid;
  final double electricityValue;
  final double waterValue;
  final double peakValue; // เฉพาะมิเตอร์ TOU
  final double offPeakValue; // เฉพาะมิเตอร์ TOU
  final int billingMonth; // เดือนของรอบบิลที่ค่านี้ใช้เป็นต้นรอบ
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