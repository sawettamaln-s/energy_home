import 'dart:math' as math;

import 'package:flutter/material.dart';

// =====================================================================
// วงแหวนความคืบหน้าของรอบบิล — ปลายเส้นมน เคลื่อนไปหาค่าใหม่แบบนุ่มๆ
// ตรงกลางวางข้อความ 2 บรรทัด (เช่น "12" / "วันที่เหลือ")
// =====================================================================
class CycleRing extends StatelessWidget {
  final double progress; // 0.0 - 1.0
  final String centerValue;
  final String centerLabel;
  final double size;
  final Color color;
  final Color trackColor;

  const CycleRing({
    super.key,
    required this.progress,
    required this.centerValue,
    required this.centerLabel,
    this.size = 92,
    this.color = Colors.white,
    this.trackColor = const Color(0x33FFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, p, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(p, color, trackColor),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(centerValue,
                    style: TextStyle(
                        color: color,
                        fontSize: size * 0.26,
                        fontWeight: FontWeight.w700,
                        height: 1.1)),
                Text(centerLabel,
                    style: TextStyle(
                        color: color.withValues(alpha: 0.8),
                        fontSize: size * 0.115,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _RingPainter(this.progress, this.color, this.trackColor);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
