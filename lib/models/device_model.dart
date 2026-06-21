class DeviceModel {
  final String id;
  final String name;
  final String category;
  final double wattage;     // วัตต์
  final double hoursPerDay; // ชั่วโมง/วัน

  DeviceModel({
    required this.id,
    required this.name,
    required this.category,
    required this.wattage,
    required this.hoursPerDay,
  });

  /// ประมาณการ kWh ต่อเดือน (30 วัน)
  double get estimatedMonthlyKwh =>
      (wattage * hoursPerDay * 30) / 1000;

  factory DeviceModel.fromFirestore(String id, Map<String, dynamic> data) {
    return DeviceModel(
      id: id,
      name: data['name'] ?? '',
      category: data['category'] ?? 'อื่นๆ',
      wattage: (data['wattage'] ?? 0).toDouble(),
      hoursPerDay: (data['hoursPerDay'] ?? 0).toDouble(),
    );
  }
}