import 'package:flutter/material.dart';

// =====================================================================
// เล่นแอนิเมชันเข้าจอครั้งเดียวตอนแสดงครั้งแรก: จางเข้า + เลื่อนขึ้นเล็กน้อย
// ใช้ [delay] ไล่จังหวะทีละส่วนให้หน้าดูมีชีวิต (โหลดข้อมูลซ้ำจะไม่เล่นใหม่
// เพราะ state ของ widget ยังอยู่) — หน่วงเวลาด้วยช่วงต้นของแอนิเมชันเอง
// (Interval) ไม่ตั้ง Timer แยก จึงไม่มีงานค้างหลัง widget ถูกถอดออก
// =====================================================================
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  static const _playTime = Duration(milliseconds: 450);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _playTime + widget.delay,
  )..forward();
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMilliseconds / (_playTime + widget.delay).inMilliseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(_curve),
        child: widget.child,
      ),
    );
  }
}
