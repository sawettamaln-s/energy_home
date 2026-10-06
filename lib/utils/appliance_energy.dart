import '../models/appliance_model.dart';

// หน่วยไฟ (kWh) ของเครื่องใช้ไฟฟ้า — สูตรเดียวทั้งแอป (หน้ารายการอุปกรณ์,
// ฟอร์มเพิ่ม/แก้ไข และแท็บอุปกรณ์ในหน้าวิเคราะห์)
//
//   หน่วย/วันที่ใช้ = วัตต์ × ชั่วโมงที่เปิด ÷ 1,000 × สัดส่วนเวลาที่ทำงานจริง
//
// เครื่องที่มีคอมเพรสเซอร์ วัตต์บนฉลากคือกำลังไฟขณะคอมเพรสเซอร์ทำงาน แต่
// คอมเพรสเซอร์ตัดเข้า-ออกเป็นรอบตามอุณหภูมิ ไม่ได้ทำงานเต็มกำลังตลอดเวลาที่
// เปิดเครื่อง ถ้าคิดเต็มทุกชั่วโมง ตัวเลขจะสูงเกินจริงหลายเท่า (ตู้เย็นเปิด 24
// ชม. คิดเต็มได้ ~2.4 หน่วย/วัน ขณะที่ฉลากเบอร์ 5 ของตู้เย็นทั่วไปอยู่ราว
// 0.6-0.9 หน่วย/วัน) จึงคูณด้วยสัดส่วนประมาณการของประเภทนั้น
// อุปกรณ์ที่เพิ่มเอง (ไม่ได้เลือกจากรายการ iconKey = null) คิดเต็ม 100%
class ApplianceEnergy {
  ApplianceEnergy._();

  // iconKey (จาก DefaultAppliances) -> สัดส่วนเวลาที่คอมเพรสเซอร์ทำงาน
  static const Map<String, double> _dutyCycle = {
    'kitchen': 0.35, // ตู้เย็น
    'ac_unit': 0.6, // เครื่องปรับอากาศ (เฉลี่ย Fixed Speed ~0.7 กับ Inverter ~0.5)
  };

  // สัดส่วนเวลาที่ทำงานเต็มกำลัง (0-1) — 1 = คิดเต็มตามชั่วโมงที่เปิด
  static double dutyCycle(String? iconKey) => _dutyCycle[iconKey] ?? 1.0;

  // หน่วยต่อวันที่เปิดใช้ จากวัตต์และชั่วโมง (ใช้ตอนกรอกฟอร์ม ก่อนบันทึก)
  static double kWhPerDay(double watt, double hours, String? iconKey) =>
      watt * hours / 1000 * dutyCycle(iconKey);

  // หน่วยต่อวันที่เปิดใช้ (รวมทุกตารางเวลา ไม่เฉลี่ยวันที่ไม่ได้ใช้)
  static double kWhPerActiveDay(ApplianceModel a) => a.schedules
      .fold(0.0, (sum, s) => sum + kWhPerDay(a.watt, s.hoursPerDay, a.iconKey));

  // หน่วยรวมในช่วง [days] วัน (30 = เดือน, 365 = ปี) ตามจำนวนวัน/สัปดาห์
  // ที่ตั้งไว้ในแต่ละตารางเวลา
  static double kWhForPeriod(ApplianceModel a, int days) => a.schedules.fold(
      0.0,
      (sum, s) =>
          sum + kWhPerDay(a.watt, s.hoursPerDay, a.iconKey) * s.days.length / 7 * days);
}
