import 'package:flutter/widgets.dart';

/// ===========================================================
/// Responsive scaling
/// ===========================================================
/// ให้ขนาดฟอนต์/ระยะห่างที่ "ยืดหยุ่นตามรุ่นจอ" โดยไม่ต้องพึ่งการเทส
/// บนเครื่องจริงทุกรุ่น — คำนวณจากความกว้างจอเทียบกับจอมาตรฐานที่ใช้
/// ออกแบบ (iPhone SE/8 = 375 logical px ซึ่งเป็นจอมือถือที่แคบที่สุด
/// ในกลุ่มที่ยังพบเห็นทั่วไป) แล้ว clamp ไว้ไม่ให้เล็ก/ใหญ่เกินไปบนจอ
/// ที่กว้างผิดปกติ (เช่น แท็บเล็ต) หรือแคบผิดปกติ
///
/// ตัวอย่างการใช้งาน:
///   fontSize: context.rf(16)   // ฟอนต์ 16 บนจอมาตรฐาน ปรับตามจอจริง
///   padding: EdgeInsets.all(context.rs(12))
const double _kBaseWidth = 375.0;
const double _kMinScale = 0.85;
const double _kMaxScale = 1.15;

extension ResponsiveScale on BuildContext {
  /// อัตราส่วนสเกลของจอปัจจุบันเทียบกับจอมาตรฐาน (คลิ้มไว้ที่ 0.85–1.15
  /// เพื่อกันไม่ให้ฟอนต์/เลย์เอาต์บิดเบี้ยวเกินไปบนจอปลายทางทั้งสองด้าน)
  double get screenScale {
    final width = MediaQuery.sizeOf(this).width;
    final raw = width / _kBaseWidth;
    return raw.clamp(_kMinScale, _kMaxScale);
  }

  /// ขนาดฟอนต์ที่ยืดหยุ่นตามจอ (responsive font)
  double rf(double baseSize) => baseSize * screenScale;

  /// ระยะห่าง/รัศมีที่ยืดหยุ่นตามจอ (responsive spacing)
  double rs(double baseValue) => baseValue * screenScale;
}