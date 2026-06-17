class ApplianceModel {
  final String id;
  final String uid;
  final String name; // ชื่ออุปกรณ์ เช่น แอร์ห้องนอน
  final String icon; // ไอคอนอุปกรณ์
  final double watt; // กำลังไฟ (วัตต์)
  final bool isActive; // เปิดใช้งานอยู่ไหม
  final List<ScheduleModel> schedules; // ตารางการใช้งาน

  ApplianceModel({
    required this.id,
    required this.uid,
    required this.name,
    this.icon = 'devices',
    required this.watt,
    this.isActive = true,
    this.schedules = const [],
  });

  // แปลงจาก Firestore เป็น Model
  factory ApplianceModel.fromMap(Map<String, dynamic> map) {
    return ApplianceModel(
      id: map['id'] ?? '',
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      icon: map['icon'] ?? 'devices',
      watt: (map['watt'] ?? 0).toDouble(),
      isActive: map['isActive'] ?? true,
      schedules: (map['schedules'] as List<dynamic>? ?? [])
          .map((s) => ScheduleModel.fromMap(s))
          .toList(),
    );
  }

  // แปลงจาก Model เป็น Map เพื่อบันทึกลง Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'name': name,
      'icon': icon,
      'watt': watt,
      'isActive': isActive,
      'schedules': schedules.map((s) => s.toMap()).toList(),
    };
  }

  // คำนวณค่าไฟต่อเดือนของอุปกรณ์นี้ (ประมาณการ)
  double get estimatedMonthlyCost {
    double totalHours = 0;
    for (var schedule in schedules) {
      totalHours += schedule.hoursPerDay * 30;
    }
    // kWh = วัตต์ × ชั่วโมง / 1000
    double kWh = watt * totalHours / 1000;
    // คูณด้วยอัตราค่าไฟเฉลี่ย 4 บาท/หน่วย
    return kWh * 4;
  }
}

class ScheduleModel {
  final List<int> days; // วันที่ใช้งาน 0=จันทร์ 6=อาทิตย์
  final String startTime; // เวลาเริ่ม เช่น '22:00'
  final String endTime; // เวลาสิ้นสุด เช่น '06:00'

  ScheduleModel({
    required this.days,
    required this.startTime,
    required this.endTime,
  });

  // คำนวณชั่วโมงการใช้งานต่อวัน
  double get hoursPerDay {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    double hours = end - start;
    // ถ้า endTime น้อยกว่า startTime แปลว่าข้ามคืน
    if (hours < 0) hours += 24;
    return hours;
  }

  double _parseTime(String time) {
    final parts = time.split(':');
    return double.parse(parts[0]) + double.parse(parts[1]) / 60;
  }

  factory ScheduleModel.fromMap(Map<String, dynamic> map) {
    return ScheduleModel(
      days: List<int>.from(map['days'] ?? []),
      startTime: map['startTime'] ?? '00:00',
      endTime: map['endTime'] ?? '00:00',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'days': days,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}