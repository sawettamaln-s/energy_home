class DefaultAppliance {
  final String name;
  final String icon;
  final double minWatt;
  final double maxWatt;
  final double defaultWatt;

  DefaultAppliance({
    required this.name,
    required this.icon,
    required this.minWatt,
    required this.maxWatt,
    required this.defaultWatt,
  });
}

class DefaultAppliances {
  static final List<DefaultAppliance> list = [
    DefaultAppliance(
      name: 'เครื่องทำน้ำอุ่นไฟฟ้า',
      icon: 'shower',
      minWatt: 3500,
      maxWatt: 8000,
      defaultWatt: 4500,
    ),
    DefaultAppliance(
      name: 'เตารีดไฟฟ้า',
      icon: 'iron',
      minWatt: 1000,
      maxWatt: 2600,
      defaultWatt: 1200,
    ),
    DefaultAppliance(
      name: 'ไดร์เป่าผม',
      icon: 'hair_dryer',
      minWatt: 1000,
      maxWatt: 2200,
      defaultWatt: 1200,
    ),
    DefaultAppliance(
      name: 'เตาไมโครเวฟ',
      icon: 'microwave',
      minWatt: 1000,
      maxWatt: 1880,
      defaultWatt: 1200,
    ),
    DefaultAppliance(
      name: 'เครื่องปรับอากาศ (Fixed Speed)',
      icon: 'ac_unit',
      minWatt: 730,
      maxWatt: 3300,
      defaultWatt: 1200,
    ),
    DefaultAppliance(
      name: 'เครื่องปรับอากาศ (Inverter)',
      icon: 'ac_unit',
      minWatt: 455,
      maxWatt: 3300,
      defaultWatt: 900,
    ),
    DefaultAppliance(
      name: 'เครื่องซักผ้า',
      icon: 'local_laundry_service',
      minWatt: 450,
      maxWatt: 2500,
      defaultWatt: 500,
    ),
    DefaultAppliance(
      name: 'หม้อหุงข้าวไฟฟ้า',
      icon: 'rice_bowl',
      minWatt: 450,
      maxWatt: 1000,
      defaultWatt: 600,
    ),
    DefaultAppliance(
      name: 'ตู้เย็น',
      icon: 'kitchen',
      minWatt: 70,
      maxWatt: 145,
      defaultWatt: 100,
    ),
    DefaultAppliance(
      name: 'พัดลมไฟฟ้า',
      icon: 'mode_fan_off',
      minWatt: 35,
      maxWatt: 80,
      defaultWatt: 50,
    ),
  ];
}