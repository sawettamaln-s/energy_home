

/// ===========================================================
/// AppSpacing
/// รวมค่าระยะห่าง/รัศมีขอบมนของแอปไว้ที่เดียว (เดิมแต่ละไฟล์เขียน
/// EdgeInsets/BorderRadius เป็นตัวเลขลอยๆ ซ้ำกันหลายจุด)
///
/// ใช้ AppSpacing.xs/sm/md/lg/xl ตอนต้องการค่าคงที่ (เหมือนเดิม)
/// หรือ context.rs(AppSpacing.md) ตอนต้องการให้ระยะยืดหยุ่นตามจอ
/// ===========================================================
class AppSpacing {
  AppSpacing._();

  // ---------- ระยะห่าง (อ้างอิงจอมาตรฐาน 375px) ----------
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  // ---------- รัศมีขอบมน ----------
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;

  // ---------- ค่าตัวเลขดิบทั้งหมดที่พบใช้อยู่ใน EdgeInsets.all() /
  // BorderRadius.circular() / Radius.circular() ทั่วแอป (ก.ย. 2026) ----------
  // ย้ายมาจากเลขลอยๆ ในแต่ละหน้า ให้มาอยู่ที่เดียว เก็บค่าเดิมไว้ทุกตัว
  // เพื่อไม่ให้หน้าตาแอปเปลี่ยน — EdgeInsets.symmetric/only/fromLTRB และ
  // SizedBox ยังไม่ได้ย้าย (ดูหมายเหตุท้ายไฟล์นี้)
  static const double v0 = 0;
  static const double v1 = 1;
  static const double v2 = 2;
  static const double v3 = 3;
  static const double v4 = 4;
  static const double v5 = 5;
  static const double v6 = 6;
  static const double v7 = 7;
  static const double v8 = 8;
  static const double v9 = 9;
  static const double v10 = 10;
  static const double v11 = 11;
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

// หมายเหตุ (ก.ย. 2026): ตั้งใจไม่ย้าย EdgeInsets.symmetric/.only/.fromLTRB
// และ SizedBox(height:/width:) เข้ามาในไฟล์นี้ทั้งหมด เพราะหลายจุดเป็น
// ขนาดโครงสร้างเฉพาะจุด (เช่น ขนาดไอคอน, ความกว้างกราฟ) ไม่ใช่ค่า "ระยะห่าง"
// ตามสัดส่วนจริงๆ — ถ้ายัดเข้าสเกลเดียวกันหมดจะทำให้ความหมายของโค้ดสับสน
// กว่าเดิม ถ้าต้องการให้ไล่ทำต่อเฉพาะจุดที่เป็น padding จริง บอกได้