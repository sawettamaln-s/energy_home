import 'package:flutter/material.dart';

/// ชุดสี/สไตล์กลางสำหรับหน้า Welcome / Login / Register / Setup
///
/// รวมไว้ที่เดียวเพื่อให้ทุกหน้าในกลุ่ม auth ใช้ปุ่ม, ช่องกรอก, ระยะห่าง,
/// และมุมโค้งชุดเดียวกันทั้งหมด (ก่อนหน้านี้แต่ละหน้า copy สไตล์ตัวเองแยกกัน
/// ทำให้ radius/ความสูงปุ่มไม่ตรงกันเป๊ะระหว่างหน้า)
class AuthStyle {
  AuthStyle._();

  static const Color green = Color(0xFF2E7D32);
  static const Color greenDark = Color(0xFF1B5E20);
  static const Color greenLight = Color(0xFF43A047);

  // ขนาด/มุมโค้งกลาง ใช้เหมือนกันทุกปุ่มหลักในกลุ่มหน้า auth ทั้งหมด
  static const double buttonHeight = 54;
  static const double radius = 16;
  static const double fieldRadius = 14;
}

/// ปุ่มหลัก (Primary) — พื้นเขียว ตัวหนังสือขาว ใช้กับ action หลักของทุกหน้า
/// (เข้าสู่ระบบ / สมัครสมาชิก / ถัดไป / เริ่มใช้งาน ฯลฯ)
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.inverted = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  // ใช้ true เมื่อวางปุ่มบนพื้นเขียวเข้ม (เช่นหน้า Welcome) — สลับเป็นพื้น
  // ขาว/ตัวหนังสือเขียวแทน ให้ปุ่มเด่นขึ้นมาจากพื้นหลังสีเข้ม
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final bgColor = inverted ? Colors.white : AuthStyle.green;
    final fgColor = inverted ? AuthStyle.green : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: AuthStyle.buttonHeight,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          disabledBackgroundColor: bgColor.withValues(alpha: 0.6),
          disabledForegroundColor: fgColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuthStyle.radius),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }
}

/// ปุ่มรอง (Secondary) — ใช้บนพื้นขาว (outline เขียว) หรือบนพื้นเขียวเข้ม
/// (outline ขาวโปร่งแสง) แล้วแต่ [onDarkBackground]
class AuthSecondaryButton extends StatelessWidget {
  const AuthSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.onDarkBackground = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final borderColor = onDarkBackground
        ? Colors.white.withValues(alpha: 0.6)
        : AuthStyle.green;
    final textColor = onDarkBackground ? Colors.white : AuthStyle.green;

    return SizedBox(
      width: double.infinity,
      height: AuthStyle.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          backgroundColor: onDarkBackground
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          side: BorderSide(color: borderColor, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuthStyle.radius),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// สไตล์ช่องกรอกกลาง — พื้นเทาอ่อนไม่มีเส้นขอบ ใช้เหมือนกันทุกช่องกรอกในกลุ่ม
/// หน้า auth (login / register / เปลี่ยนรหัสผ่าน ฯลฯ)
InputDecoration authFieldDecoration({
  required String hint,
  required IconData icon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400),
    prefixIcon: Icon(icon, color: Colors.grey.shade500),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.grey.shade50,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AuthStyle.fieldRadius),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AuthStyle.fieldRadius),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AuthStyle.fieldRadius),
      borderSide: const BorderSide(color: AuthStyle.green, width: 1.5),
    ),
  );
}

/// หัวข้อเล็กเหนือช่องกรอก — ใช้รูปแบบเดียวกันทุกช่องทุกหน้า
class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w600));
  }
}

/// กล่องข้อความ error สีแดงอ่อน — ใช้เหมือนกันทุกหน้า (เดิม login กับ
/// register copy โค้ดชุดนี้แยกกัน)
class AuthErrorBox extends StatelessWidget {
  const AuthErrorBox(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// โลโก้แอป (วงกลม/สี่เหลี่ยมมุมโค้งพื้นเขียว + ไอคอนสายฟ้า) — ใช้ทั้งบนพื้น
/// เขียวเข้ม (Welcome) และพื้นขาว (Login/Register) โดยสลับสีตาม
/// [onDarkBackground]
class AuthLogoBadge extends StatelessWidget {
  const AuthLogoBadge({
    super.key,
    this.size = 76,
    this.iconSize = 44,
    this.onDarkBackground = false,
  });

  final double size;
  final double iconSize;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final bg = onDarkBackground ? Colors.white : AuthStyle.green;
    final iconColor = onDarkBackground ? AuthStyle.green : Colors.white;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: (onDarkBackground ? Colors.black : AuthStyle.green)
                .withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(Icons.bolt, color: iconColor, size: iconSize),
    );
  }
}