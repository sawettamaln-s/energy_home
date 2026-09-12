// GENERATED FILE — อย่าแก้ตรงนี้ตรงๆ
// สร้างจาก tool/forecast_synth/seasonal_curves.json
// โดย tool/forecast_synth/export_curves_to_dart.py
// รันสคริปต์นั้นใหม่ทุกครั้งที่มีข้อมูลจริงเพิ่ม เพื่ออัปเดตไฟล์นี้

/// ตัวคูณตามฤดูกาลของแต่ละเคส (ม.ค.=index 0 ... ธ.ค.=index 11)
/// ค่าเฉลี่ยรวม 12 เดือน = 1.0 เสมอ
/// ผสมจากข้อมูลสมมติ (synthetic) + ข้อมูลจริงเท่าที่มี ณ ตอน export
class SeasonalCurves {
  static const Map<String, List<double>> elec = {
    'bangkok_normal': [0.7912, 0.9558, 1.1146, 1.2681, 1.2131, 1.1180, 1.0456, 0.9889, 0.9214, 0.9102, 0.9046, 0.7685],
    'bangkok_tou': [0.7877, 0.9525, 1.1030, 1.2570, 1.2136, 1.1106, 1.0392, 1.0125, 0.9589, 0.9150, 0.8987, 0.7513],
    'upcountry_normal': [0.7462, 0.7451, 1.0178, 1.2873, 1.2321, 1.2000, 1.1451, 1.1075, 1.0607, 0.9680, 0.7459, 0.7443],
    'upcountry_tou': [0.8140, 0.8079, 0.9981, 1.2029, 1.1597, 1.1255, 1.1102, 1.0688, 1.0505, 0.9959, 0.8333, 0.8332],
  };

  static const Map<String, List<double>> water = {
    'bangkok_normal': [0.9275, 0.9827, 1.0365, 1.0797, 1.0670, 1.0312, 1.0131, 1.0177, 0.9790, 0.9766, 0.9727, 0.9162],
    'bangkok_tou': [0.9296, 0.9830, 1.0350, 1.0912, 1.0752, 1.0370, 1.0065, 0.9975, 0.9801, 0.9773, 0.9704, 0.9172],
    'upcountry_normal': [0.8898, 0.8984, 1.0123, 1.1064, 1.0881, 1.0832, 1.0612, 1.0490, 1.0268, 0.9904, 0.9013, 0.8931],
    'upcountry_tou': [0.8838, 0.9041, 1.0104, 1.1091, 1.0975, 1.0794, 1.0578, 1.0398, 1.0323, 0.9886, 0.9006, 0.8967],
  };

  /// รวม area+meterType เป็น case key ให้ตรงกับที่ใช้ในนี้
  static String caseKeyFor({required String area, required String meterType}) {
    final region = area == 'bangkok' ? 'bangkok' : 'upcountry';
    final meter = meterType == 'tou' ? 'tou' : 'normal';
    return '${region}_$meter';
  }
}
