import 'package:flutter/material.dart';

import '../../widgets/auth_widgets.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// หน้าแรกสุดของแอป (ก่อนเข้าสู่ระบบ/สมัครสมาชิก) — เดิมระบบไม่มีหน้านี้
/// (AuthGate พาผู้ใช้ที่ยังไม่ login เข้าหน้า Login ตรงๆ) เพิ่มเข้ามาให้
/// ผู้ใช้ใหม่เห็นภาพรวมแอปก่อน แล้วค่อยเลือกเข้าสู่ระบบ/สมัครสมาชิก
/// ดีไซน์อ้างอิงโทนพื้นเขียวเข้ม + ปุ่มคู่ด้านล่าง (ปุ่มขาวตัน + ปุ่มขอบขาว
/// โปร่งแสง) แต่คงชุดสีเขียวเดิมของแอป (AuthStyle.green) ไม่เปลี่ยนธีม
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // พื้นหลังไล่เฉดเขียว (มุมบนซ้ายอ่อนกว่า ไล่เข้มลงมุมล่างขวา) แทน
          // สีเขียวตันสีเดียวแบบเดิม ให้มีมิติ/ความลึกมากขึ้น
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AuthStyle.greenLight,
                  AuthStyle.green,
                  AuthStyle.greenDark,
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // แสงเรืองนุ่มๆ มุมบนขวา — วงกลมโปร่งแสงเบลอขอบ จำลองแสงตกกระทบ
          Positioned(
            top: -70,
            right: -60,
            child: _GlowOrb(size: 260, opacity: 0.16),
          ),
          // เงานุ่มๆ มุมล่างซ้าย ให้มีน้ำหนัก/ความลึกถ่วงองค์ประกอบ
          Positioned(
            bottom: -90,
            left: -80,
            child: _GlowOrb(
              size: 280,
              opacity: 0.14,
              color: AuthStyle.greenDark,
            ),
          ),
          // จุดแสงเล็กแซมกลางค่อนบน เพิ่มลูกเล่นให้พื้นหลังไม่ราบเรียบไปหมด
          Positioned(
            top: 90,
            left: -30,
            child: _GlowOrb(size: 120, opacity: 0.12),
          ),

          SafeArea(child: _WelcomeContent()),
        ],
      ),
    );
  }
}

/// วงกลมแสง/เงาเบลอ — ใช้ BoxShadow ขนาดใหญ่แทนการเบลอภาพจริง (เบากว่า
/// BackdropFilter และไม่ต้องพึ่ง asset ภาพ) ให้ความรู้สึกแสงกระจายนุ่มๆ
class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.opacity, this.color});

  final double size;
  final double opacity;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.withValues(alpha: opacity),
          boxShadow: [
            BoxShadow(
              color: c.withValues(alpha: opacity * 0.6),
              blurRadius: size * 0.6,
              spreadRadius: size * 0.15,
            ),
          ],
        ),
      ),
    );
  }
}

/// เนื้อหาหลักของหน้า Welcome (โลโก้ + ชื่อแอป + ปุ่ม) แยกออกมาจาก build()
/// เดิม เพื่อให้ชั้น Stack ด้านนอกดูแล background/แสงเงาอย่างเดียว
class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
              // ภาพประกอบตรงกลาง — ใช้ไอคอนแทนภาพประกอบ (ไม่มีไฟล์ภาพ)
              // วางเป็นวงกลมซ้อนกันคล้ายลูกโป่งลอย ให้ความรู้สึกเดียวกับ
              // ภาพ reference โดยไม่ต้องพึ่ง asset ภายนอก
              Expanded(
                flex: 5,
                child: Center(
                  child: _WelcomeIllustration(),
                ),
              ),

              // ชื่อแอปและคำโปรย
              const Text(
                'EnergyHome',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'จดบันทึกและติดตามค่าไฟ ค่าน้ำในบ้านคุณ\n'
                'ได้ง่ายๆ พร้อมวิเคราะห์การใช้งานทุกเดือน',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),

              const Spacer(flex: 4),

              // ปุ่มเข้าสู่ระบบ / สมัครสมาชิก — ใช้ widget กลางชุดเดียวกับ
              // ปุ่มในหน้า Login/Register/Setup ทั้งหมด (แค่กลับสี inverted
              // เพราะพื้นหลังหน้านี้เป็นเขียวเข้ม)
              AuthPrimaryButton(
                label: 'เข้าสู่ระบบ',
                inverted: true,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              AuthSecondaryButton(
                label: 'สร้างบัญชีใหม่',
                onDarkBackground: true,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegisterScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
  }
}

/// ภาพประกอบกลางหน้า — วงกลมโลโก้หลัก + ไอคอนลอยรอบๆ (มิเตอร์ไฟ, หยดน้ำ,
/// กราฟ) สื่อถึงเนื้อหาแอป (พลังงาน+น้ำ+การวิเคราะห์) แทนภาพ illustration
/// จริงที่ต้องใช้ asset ภายนอก
class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // วงแหวนพื้นหลังจางๆ
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),

          // โลโก้หลักตรงกลาง
          const AuthLogoBadge(size: 92, iconSize: 52, onDarkBackground: true),

          // ไอคอนลอยรอบๆ
          const Positioned(
            top: 6,
            left: 10,
            child: _FloatingIcon(icon: Icons.water_drop_outlined),
          ),
          const Positioned(
            top: 18,
            right: 0,
            child: _FloatingIcon(icon: Icons.show_chart),
          ),
          const Positioned(
            bottom: 12,
            left: 0,
            child: _FloatingIcon(icon: Icons.electric_meter_outlined),
          ),
          const Positioned(
            bottom: 0,
            right: 14,
            child: _FloatingIcon(icon: Icons.eco_outlined),
          ),
        ],
      ),
    );
  }
}

class _FloatingIcon extends StatelessWidget {
  const _FloatingIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}