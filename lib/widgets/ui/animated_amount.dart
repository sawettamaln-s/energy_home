import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// =====================================================================
// ตัวเลขจำนวนเงิน/หน่วยที่นับขึ้นลงไปหาค่าใหม่แบบนุ่มๆ (ค่าเปลี่ยนเมื่อโหลด
// ข้อมูลใหม่ หรือแสดงครั้งแรก) — จบที่ค่าจริงเสมอ รูปแบบตัวเลขตาม [pattern]
// ต่อท้ายด้วย [suffix] เช่น ' บาท'
// =====================================================================
class AnimatedAmount extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final String suffix;
  final String pattern;
  final Duration duration;
  final TextAlign? textAlign;

  const AnimatedAmount({
    super.key,
    required this.value,
    this.style,
    this.suffix = ' บาท',
    this.pattern = '#,##0.00',
    this.duration = const Duration(milliseconds: 750),
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat(pattern);
    // ตัวเลขกว้างเท่ากันทุกหลัก ข้อความไม่กระตุกระหว่างนับ
    final numberStyle = (style ?? const TextStyle())
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        '${formatter.format(v)}$suffix',
        style: numberStyle,
        textAlign: textAlign,
      ),
    );
  }
}
