import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controller สำหรับรับค่าจาก TextField
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // ตัวแปรสถานะ
  bool _isLoading = false; // กำลังโหลดอยู่ไหม
  bool _obscurePassword = true; // ซ่อน/แสดง password
  String _errorMessage = ''; // ข้อความ error

  @override
  void dispose() {
    // คืน memory เมื่อออกจากหน้านี้
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ฟังก์ชัน Login
  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // ถ้าสำเร็จ Firebase จะ trigger AuthState เองอัตโนมัติ
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _errorMessage = 'ไม่พบบัญชีผู้ใช้นี้ในระบบค่ะ กรุณาตรวจสอบอีเมลของคุณอีกครั้ง';
            break;
          case 'wrong-password':
            _errorMessage = 'รหัสผ่านไม่ถูกต้องค่ะ กรุณาลองใหม่อีกครั้ง';
            break;
          case 'invalid-email':
            _errorMessage = 'รูปแบบอีเมลไม่ถูกต้องค่ะ กรุณาตรวจสอบอีเมลของคุณ';
            break;
          default:
            _errorMessage = 'เกิดข้อผิดพลาดบางอย่างค่ะ กรุณาลองใหม่อีกครั้ง';
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ส่งอีเมลรีเซ็ตรหัสผ่าน — เปิด dialog ให้กรอกอีเมล (ดึงจากช่อง login มาเติม
  // ให้ล่วงหน้าถ้ามีอยู่แล้ว) แล้วยิง sendPasswordResetEmail ของ Firebase
  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController =
        TextEditingController(text: _emailController.text.trim());
    String? dialogError;
    bool isSending = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('ลืมรหัสผ่าน?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'กรอกอีเมลที่ใช้สมัคร ระบบจะส่งลิงก์สำหรับตั้งรหัสผ่านใหม่ไปให้ค่ะ',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'example@email.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final email = resetEmailController.text.trim();
                          if (email.isEmpty) {
                            setDialogState(
                                () => dialogError = 'กรุณากรอกอีเมลค่ะ');
                            return;
                          }
                          setDialogState(() {
                            isSending = true;
                            dialogError = null;
                          });
                          try {
                            await FirebaseAuth.instance
                                .sendPasswordResetEmail(email: email);
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'ส่งลิงก์รีเซ็ตรหัสผ่านไปที่ $email แล้วค่ะ ตรวจสอบอีเมล (รวมถึง Junk/Spam) นะคะ'),
                                backgroundColor: const Color(0xFF2E7D32),
                              ),
                            );
                          } on FirebaseAuthException catch (e) {
                            setDialogState(() {
                              isSending = false;
                              switch (e.code) {
                                case 'user-not-found':
                                  dialogError = 'ไม่พบบัญชีผู้ใช้ที่ใช้อีเมลนี้ค่ะ';
                                  break;
                                case 'invalid-email':
                                  dialogError = 'รูปแบบอีเมลไม่ถูกต้องค่ะ';
                                  break;
                                default:
                                  dialogError = 'เกิดข้อผิดพลาดบางอย่างค่ะ กรุณาลองใหม่อีกครั้ง';
                              }
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                  child: isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('ส่งลิงก์'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),

              // โลโก้และชื่อแอป
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.bolt,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'EnergyHome',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                    const Text(
                      'ติดตามพลังงานในบ้านของคุณ',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // ช่อง Email
              const Text('อีเมล',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'example@email.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ช่อง Password
              const Text('รหัสผ่าน',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword, // ซ่อน/แสดงตัวอักษร
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ลิงก์ลืมรหัสผ่าน — จัดชิดขวาใต้ช่อง password ตามตำแหน่งที่
              // คนคุ้นเคยที่สุด (Gmail, Facebook ฯลฯ ก็วางตรงนี้เหมือนกัน)
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _showForgotPasswordDialog,
                  child: const Text(
                    'ลืมรหัสผ่าน?',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // แสดง error ถ้ามี
              if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),

              const SizedBox(height: 24),

              // ปุ่ม Login
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('เข้าสู่ระบบ',
                          style: TextStyle(fontSize: 16)),
                ),
              ),

              const SizedBox(height: 16),

              // ลิงก์ไปหน้าสมัครสมาชิก
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('ยังไม่มีบัญชี? '),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'สมัครสมาชิก',
                      style: TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}