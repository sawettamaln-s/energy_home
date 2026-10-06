import '../models/appliance_model.dart';
import 'default_appliances.dart';

// หน่วยไฟ (kWh) ของเครื่องใช้ไฟฟ้า — สูตรมาตรฐานแบบเดียวกับเว็บคำนวณค่าไฟ
// ทั่วไป ใช้ทั้งหน้ารายการอุปกรณ์และฟอร์มเพิ่ม/แก้ไข
//
//   หน่วย/วันที่ใช้ = วัตต์ × ชั่วโมงที่ใช้ ÷ 1,000
//
// ตู้เย็น/แอร์ คอมเพรสเซอร์ไม่ได้ทำงานตลอดเวลาที่เปิด ฟอร์มจึงแนะนำให้กรอก
// ชั่วโมงที่เครื่องทำงานจริง แทนการปรับสูตร
class ApplianceEnergy {
  ApplianceEnergy._();

  // หน่วยต่อวันที่ใช้ จากวัตต์และชั่วโมง
  static double kWhPerDay(double watt, double hours) => watt * hours / 1000;

  // ประเภทของอุปกรณ์ที่บันทึกแล้ว: iconKey ที่เก็บตอนเลือก ข้อมูลเก่าที่ยังไม่มี
  // iconKey จับคู่จากชื่อกับรายการสามัญประจำบ้าน
  static String? typeKey(ApplianceModel a) =>
      a.iconKey ?? DefaultAppliances.byName(a.name)?.icon;

  // หน่วยต่อวันที่ใช้ (รวมทุกตารางเวลา ไม่เฉลี่ยวันที่ไม่ได้ใช้)
  static double kWhPerActiveDay(ApplianceModel a) =>
      a.schedules.fold(0.0, (sum, s) => sum + kWhPerDay(a.watt, s.hoursPerDay));

  // หน่วยรวมในช่วง [days] วัน (30 = เดือน, 365 = ปี) ตามจำนวนวัน/สัปดาห์
  // ที่ตั้งไว้ในแต่ละตารางเวลา
  static double kWhForPeriod(ApplianceModel a, int days) => a.schedules.fold(
      0.0, (sum, s) => sum + kWhPerDay(a.watt, s.hoursPerDay) * s.days.length / 7 * days);
}
