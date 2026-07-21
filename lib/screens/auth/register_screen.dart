import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/auth_widgets.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _errorMessage = '';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    // เช็คว่ากรอกครบไหม
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'กรุณากรอกชื่อ-นามสกุลของคุณก่อน');
      return;
    }

    // เช็คว่า Password ตรงกันไหม
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'รหัสผ่านที่กรอกไม่ตรงกัน กรุณาตรวจสอบอีกครั้ง');
      return;
    }

    // เช็คว่า Password ยาวพอไหม
    if (_passwordController.text.length < 6) {
      setState(() => _errorMessage = 'รหัสผ่านต้องมีความยาวอย่างน้อย 6 ตัวอักษร');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // สร้างบัญชีใหม่ใน Firebase
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // บันทึกชื่อผู้ใช้
      await userCredential.user?.updateDisplayName(_nameController.text.trim());

      // สมัครสำเร็จ — ต้องกลับไปให้ถึง AuthGate ที่ฐานสุดของ stack เสมอ
      // (ไม่ใช่แค่ pop ทีเดียว) เพราะตอนนี้ Register อาจถูก push มาจาก
      // Welcome ตรงๆ (1 ชั้น) หรือมาจาก Welcome -> Login -> Register (2
      // ชั้น) ก็ได้ — pop ครั้งเดียวแบบเดิมจะกลับไปแค่หน้า Login เฉยๆ ไม่ถึง
      // AuthGate ที่ StreamBuilder จะพาไปหน้า Setup ต่อให้อัตโนมัติ
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'email-already-in-use':
            _errorMessage = 'อีเมลนี้ถูกใช้สมัครสมาชิกไปแล้ว กรุณาใช้อีเมลอื่น';
            break;
          case 'invalid-email':
            _errorMessage = 'รูปแบบอีเมลไม่ถูกต้อง กรุณาตรวจสอบอีเมลของคุณ';
            break;
          case 'weak-password':
            _errorMessage = 'รหัสผ่านนี้ยังไม่ปลอดภัยพอ กรุณาตั้งรหัสผ่านที่คาดเดายากขึ้น';
            break;
          default:
            _errorMessage = 'เกิดข้อผิดพลาดบางอย่าง กรุณาลองใหม่อีกครั้ง';
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // โลโก้และหัวข้อ — โครงเดียวกับหน้า Login เพื่อความสมดุล/
              // ทิศทางเดียวกันทั้งกลุ่มหน้า auth
              Center(
                child: Column(
                  children: [
                    const AuthLogoBadge(),
                    const SizedBox(height: 16),
                    const Text(
                      'สร้างบัญชีใหม่',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AuthStyle.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'สมัครสมาชิกเพื่อเริ่มติดตามพลังงานในบ้านคุณ',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ช่องชื่อ
              const AuthFieldLabel('ชื่อ-นามสกุล'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: authFieldDecoration(
                  hint: 'กรอกชื่อของคุณ',
                  icon: Icons.person_outlined,
                ),
              ),

              const SizedBox(height: 16),

              // ช่อง Email
              const AuthFieldLabel('อีเมล'),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: authFieldDecoration(
                  hint: 'example@email.com',
                  icon: Icons.email_outlined,
                ),
              ),

              const SizedBox(height: 16),

              // ช่อง Password
              const AuthFieldLabel('รหัสผ่าน'),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: authFieldDecoration(
                  hint: 'อย่างน้อย 6 ตัวอักษร',
                  icon: Icons.lock_outlined,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ช่องยืนยัน Password
              const AuthFieldLabel('ยืนยันรหัสผ่าน'),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: authFieldDecoration(
                  hint: 'กรอกรหัสผ่านอีกครั้ง',
                  icon: Icons.lock_outlined,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setState(() =>
                        _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ),
              ),

              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 14),
                AuthErrorBox(_errorMessage),
              ],

              const SizedBox(height: 24),

              // ปุ่มสมัคร
              AuthPrimaryButton(
                label: 'สมัครสมาชิก',
                isLoading: _isLoading,
                onPressed: _register,
              ),
              const SizedBox(height: 16),

              // ลิงก์กลับไปเข้าสู่ระบบ — แทนที่ปุ่มย้อนกลับเดิม เผื่อกรณี
              // ผู้ใช้มีบัญชีอยู่แล้วแต่หลงเข้ามาหน้าสมัครสมาชิก
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('มีบัญชีอยู่แล้ว? ',
                      style: TextStyle(color: Colors.grey)),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'เข้าสู่ระบบ',
                      style: TextStyle(
                        color: AuthStyle.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}