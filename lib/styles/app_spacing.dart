

/// ===========================================================
/// AppSpacing
/// รวมค่าระยะห่าง/รัศมีขอบมนของแอปไว้ที่เดียว
///
/// ใช้ AppSpacing.vN (N = จำนวน px) กับ EdgeInsets.all() และ
/// BorderRadius/Radius.circular()
/// ===========================================================
class AppSpacing {
  AppSpacing._();

  // ---------- ค่าที่ใช้จริงใน EdgeInsets.all() / BorderRadius.circular() /
  // Radius.circular() ทั่วแอป ----------
  // EdgeInsets.symmetric/only/fromLTRB และ SizedBox ยังใช้ตัวเลขตรงๆ ได้
  // (ดูหมายเหตุท้ายไฟล์)
  static const double v0 = 0;
  static const double v1 = 1;
  static const double v2 = 2;
  static const double v3 = 3;
  static const double v4 = 4;
  static const double v5 = 5;
  static const double v6 = 6;
  static const double v7 = 7;
  static const double v8 = 8;
  static const double v10 = 10;
  static const double v12 = 12;
  static const double v13 = 13;
  static const double v14 = 14;
  static const double v16 = 16;
  static const double v18 = 18;
  static const double v20 = 20;
  static const double v24 = 24;
  static const double v30 = 30;
  static const double v32 = 32;
  static const double v54 = 54;
}

// หมายเหตุ: EdgeInsets.symmetric/.only/.fromLTRB และ SizedBox(height:/width:)
// ไม่บังคับให้ใช้ค่าจากไฟล์นี้ เพราะหลายจุดเป็นขนาดโครงสร้างเฉพาะที่ (เช่น
// ขนาดไอคอน, ความกว้างกราฟ) ไม่ใช่ "ระยะห่าง" ตามสเกล