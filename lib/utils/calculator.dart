import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'tariff_tables.dart';

// การคิดค่าไฟ/ค่าน้ำของแอป: ผูกตารางอัตรา (tariff_tables.dart) เข้ากับประเภท
// อัตราของผู้ใช้ และค่า Ft ที่ผู้ดูแลตั้งใน Firestore
//   ค่า Ft : กกพ. https://www.erc.or.th/th/news-release/3458 (งวด ก.ย.-ธ.ค. 2569 = 16.23 สตางค์)

// ค่า Ft ที่แอปใช้ และวันที่เริ่มใช้งวดนั้น (null = ผู้ดูแลยังไม่ได้ระบุ)
typedef FtInfo = ({double rate, DateTime? effectiveFrom});

class EnergyCalculator {
  // ค่า Ft งวดล่าสุดที่ผู้ดูแลตั้งไว้ใน app_config/electricity_rates (แก้ผ่าน
  // Firebase Console ทุกครั้งที่ กกพ. ประกาศงวดใหม่ ทุก 4 เดือน: ม.ค./พ.ค./ก.ย.)
  // อ่านไม่ได้ (ออฟไลน์/ยังไม่มีเอกสาร) ใช้ค่าของงวด ก.ย.-ธ.ค. 2569 แทน
  static const double defaultFtRate = 0.1623;

  static Future<double> getFtRate() async => (await getFtInfo()).rate;

  // ตัวอ่านเอกสาร app_config/electricity_rates — เทสเปลี่ยนเป็นตัวปลอมได้
  // (คืนค่าเดิมด้วย resetFtSource)
  static Future<Map<String, dynamic>?> Function() ftDocLoader = _readFtDoc;

  static Future<Map<String, dynamic>?> _readFtDoc() async =>
      (await FirebaseFirestore.instance
              .collection('app_config')
              .doc('electricity_rates')
              .get())
          .data();

  // จำค่า Ft ที่อ่านได้ไว้ชั่วคราว — การคิดเงินทีละหลายยอด (คิดใหม่ทั้งรอบ, ปิด
  // บิลย้อนหลัง) จึงไม่อ่าน Firestore ซ้ำทุกยอด อ่านไม่สำเร็จไม่จำ ครั้งหน้าลองใหม่
  static const Duration ftCacheDuration = Duration(minutes: 10);
  static FtInfo? _ftCache;
  static DateTime? _ftCachedAt;

  // ft_rate = บาท/หน่วย, ft_effective_from = วันเริ่มงวด (ISO เช่น 2026-09-01)
  static Future<FtInfo> getFtInfo() async {
    final cached = _ftCache;
    final cachedAt = _ftCachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < ftCacheDuration) {
      return cached;
    }
    try {
      final info = ftInfoFromMap(await ftDocLoader());
      rememberFtInfo(info);
      return info;
    } catch (e) {
      return (rate: defaultFtRate, effectiveFrom: null);
    }
  }

  // ใช้ค่า Ft ที่เพิ่งอ่านมาจากที่อื่น (เช่น FirestoreService.getFtInfo ตอนโหลด
  // หน้าหลัก) เป็นค่าที่จำไว้ การคิดเงินหลังจากนั้นจึงใช้งวดล่าสุดทันที
  static void rememberFtInfo(FtInfo info) {
    _ftCache = info;
    _ftCachedAt = DateTime.now();
  }

  @visibleForTesting
  static void resetFtSource() {
    ftDocLoader = _readFtDoc;
    _ftCache = null;
    _ftCachedAt = null;
  }

  // แปลงเอกสาร app_config/electricity_rates เป็น FtInfo (ไม่มี ft_rate = ค่า default)
  static FtInfo ftInfoFromMap(Map<String, dynamic>? data) => (
        rate: ((data?['ft_rate'] ?? defaultFtRate) as num).toDouble(),
        effectiveFrom: DateTime.tryParse('${data?['ft_effective_from'] ?? ''}'),
      );

  // ค่า Ft ประกาศใหม่ทุก 4 เดือน — งวดที่ใช้อยู่เริ่มก่อน [now] เกิน 4 เดือน
  // แปลว่าผู้ดูแลยังไม่ได้อัปเดตงวดใหม่ (ไม่รู้วันเริ่มงวด = ตัดสินไม่ได้ คืน false)
  static bool isFtOutdated(DateTime? effectiveFrom, DateTime now) {
    if (effectiveFrom == null) return false;
    final nextPeriod =
        DateTime(effectiveFrom.year, effectiveFrom.month + 4, effectiveFrom.day);
    return !now.isBefore(nextPeriod);
  }

  // รหัสประเภทอัตราตามที่พิมพ์บนใบแจ้งหนี้ — อัตราเท่ากัน แต่ กฟน. กับ กฟภ.
  // ตั้งชื่อต่างกัน: กฟน. 1.1 / 1.2 (TOU = 1.3.2), กฟภ. 1.1.1 / 1.1.2 (TOU = 1.2.2)
  static String tariffCode(String tariff, String area) {
    final isBangkok = area == 'bangkok';
    if (tariff == tariffSmall) return isBangkok ? '1.1' : '1.1.1';
    return isBangkok ? '1.2' : '1.1.2';
  }

  static String touCode(String area) => area == 'bangkok' ? '1.3.2' : '1.2.2';

  // ==================== ค่าไฟฟ้า ====================
  // ตารางอัตรา/สูตรอยู่ที่ TariffTables (tariff_tables.dart) ที่เดียว — ที่นี่
  // แค่ผูกกับประเภทอัตราของผู้ใช้และค่า Ft จาก Firestore

  // ประเภทอัตราค่าไฟของมิเตอร์ปกติ (ผู้ใช้เลือกตามใบแจ้งหนี้ — UserModel.electricityTariff)
  // tariffStandard = ใช้เกิน 150 หน่วย กฟน. 1.2 / กฟภ. 1.1.2 (ค่าเริ่มต้น บ้านส่วนใหญ่ที่มิเตอร์เกิน
  //   5 แอมแปร์ หรือใช้เกิน 150 หน่วย/เดือน)
  // tariffSmall    = ใช้ไม่เกิน 150 หน่วย กฟน. 1.1 / กฟภ. 1.1.1 (มิเตอร์ไม่เกิน 5 แอมแปร์ ที่ใช้ไม่เกิน 150
  //   หน่วย/เดือนติดต่อกัน 3 เดือน)
  static const String tariffStandard = 'standard';
  static const String tariffSmall = 'small';

  // คำนวณค่าไฟฟ้าแบบปกติ
  // area: 'bangkok' = MEA, 'province' = PEA (ทั้งสองใช้ตารางอัตราเดียวกัน)
  // tariff: ประเภทอัตรา (ดู tariffStandard/tariffSmall) ไม่ส่ง = ใช้เกิน 150 หน่วย
  // ใช้ 0 หน่วยยังเสียค่าบริการรายเดือน (+ VAT) เหมือนใบแจ้งหนี้จริง
  static Future<double> calculateElectricity(
    double units,
    String area, {
    String tariff = tariffStandard,
  }) async {
    // 0 หน่วยไม่มีค่า Ft ให้คิด ไม่ต้องอ่าน Firestore
    final ftRate = units > 0 ? await getFtRate() : 0.0;
    return electricityCost(units, ftRate: ftRate, tariff: tariff);
  }

  // ค่าไฟฟ้าแบบปกติด้วยค่า Ft ที่ส่งมา (ไม่อ่าน Firestore) — ใช้เมื่อต้องคิด
  // หลายยอดต่อกัน เช่น คาดการณ์หลายเดือนในหน้าวิเคราะห์ ให้อ่าน Ft ครั้งเดียว
  static double electricityCost(
    double units, {
    required double ftRate,
    String tariff = tariffStandard,
  }) =>
      TariffTables.electricity(units, ftRate: ftRate, small: tariff == tariffSmall);

  // คำนวณค่าไฟฟ้าแบบ TOU
  static Future<double> calculateElectricityTOU({
    required double peakUnits,
    required double offPeakUnits,
  }) async {
    final ftRate = peakUnits > 0 || offPeakUnits > 0 ? await getFtRate() : 0.0;
    return electricityTouCost(
      peakUnits: peakUnits,
      offPeakUnits: offPeakUnits,
      ftRate: ftRate,
    );
  }

  // ค่าไฟฟ้าแบบ TOU ด้วยค่า Ft ที่ส่งมา (ไม่อ่าน Firestore)
  static double electricityTouCost({
    required double peakUnits,
    required double offPeakUnits,
    required double ftRate,
  }) =>
      TariffTables.electricityTou(peakUnits, offPeakUnits, ftRate: ftRate);

  // คำนวณค่าไฟตามประเภทมิเตอร์ — TOU ใช้ peakUnits/offPeakUnits,
  // มิเตอร์ปกติใช้ units ตามประเภทอัตรา [tariff] (TOU ไม่ใช้ค่านี้)
  static Future<double> calculateElectricityByType({
    required double units,
    required String meterType,
    required String area,
    double peakUnits = 0,
    double offPeakUnits = 0,
    String tariff = tariffStandard,
  }) async {
    if (meterType == 'tou') {
      return calculateElectricityTOU(
        peakUnits: peakUnits,
        offPeakUnits: offPeakUnits,
      );
    } else {
      return calculateElectricity(units, area, tariff: tariff);
    }
  }

  // ==================== ค่าน้ำประปา ====================

  // area 'bangkok' = กปน. (MWA), อื่นๆ = กปภ. (PWA)
  static double calculateWater(double units, String area) => area == 'bangkok'
      ? TariffTables.waterMwaCost(units)
      : TariffTables.waterPwaCost(units);

  // หน่วยที่ใช้ = เลขใหม่ - เลขเดิม (ดู TariffTables.unitsUsed) ไม่มีทางติดลบ
  static double calculateUsed(double current, double previous) =>
      TariffTables.unitsUsed(current, previous);
}
