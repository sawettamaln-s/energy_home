import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/auth_widgets.dart';
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
      // เข้าสู่ระบบสำเร็จ — ต้อง pop กลับไปที่ AuthGate ที่ฐานสุดของ stack
      // เอง (เมื่อก่อน Login คือเนื้อหาที่ AuthGate render ตรงๆ ไม่ได้ push
      // เลยแค่รอ authStateChanges() แล้วปล่อยให้ AuthGate build ใหม่ก็พอ
      // แต่ตอนนี้ Login ถูก push มาจากหน้า Welcome แล้ว ถ้าไม่ pop ออก
      // หน้า Login จะค้างอยู่ทับ AuthGate ที่อัปเดตอยู่ข้างล่างไปเรื่อยๆ)
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _errorMessage = 'ไม่พบบัญชีผู้ใช้นี้ในระบบ กรุณาตรวจสอบอีเมลของคุณอีกครั้ง';
            break;
          case 'wrong-password':
            _errorMessage = 'รหัสผ่านไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง';
            break;
          case 'invalid-email':
            _errorMessage = 'รูปแบบอีเมลไม่ถูกต้อง กรุณาตรวจสอบอีเมลของคุณ';
            break;
          default:
            _errorMessage = 'เกิดข้อผิดพลาดบางอย่าง กรุณาลองใหม่อีกครั้ง';
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
                    'กรอกอีเมลที่ใช้สมัคร ระบบจะส่งลิงก์สำหรับตั้งรหัสผ่านใหม่ไปให้',
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
                                () => dialogError = 'กรุณากรอกอีเมล');
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
                                    'ส่งลิงก์รีเซ็ตรหัสผ่านไปที่ $email แล้ว ตรวจสอบอีเมล (รวมถึง Junk/Spam) '),
                                backgroundColor: AuthStyle.green,
                              ),
                            );
                          } on FirebaseAuthException catch (e) {
                            setDialogState(() {
                              isSending = false;
                              switch (e.code) {
                                case 'user-not-found':
                                  dialogError = 'ไม่พบบัญชีผู้ใช้ที่ใช้อีเมลนี้';
                                  break;
                                case 'invalid-email':
                                  dialogError = 'รูปแบบอีเมลไม่ถูกต้อง';
                                  break;
                                default:
                                  dialogError = 'เกิดข้อผิดพลาดบางอย่าง กรุณาลองใหม่อีกครั้ง';
                              }
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AuthStyle.green,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                // บังคับความสูงขั้นต่ำเท่าพื้นที่จอ เพื่อให้ Spacer จัด layout
                // แบบสมดุลได้บนจอสูง แต่ยังยุบ/เลื่อนได้ปกติเวลาคีย์บอร์ดเปิด
                // บนจอเตี้ยหรือ Android รุ่นที่มี navigation bar กินพื้นที่เยอะ
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 32),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(flex: 2),

                      // โลโก้และชื่อแอป
                      Center(
                        child: Column(
                          children: [
                            const AuthLogoBadge(),
                            const SizedBox(height: 16),
                            const Text(
                              'ยินดีต้อนรับกลับมา',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AuthStyle.green,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'เข้าสู่ระบบเพื่อติดตามพลังงานในบ้านของคุณ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(flex: 2),

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
                          hint: '••••••••',
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
                              color: AuthStyle.green,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),

                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        AuthErrorBox(_errorMessage),
                      ],

                      const SizedBox(height: 20),

                      // ปุ่ม Login
                      AuthPrimaryButton(
                        label: 'เข้าสู่ระบบ',
                        isLoading: _isLoading,
                        onPressed: _login,
                      ),

                      const Spacer(flex: 1),

                      // ลิงก์ไปหน้าสมัครสมาชิก
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('ยังไม่มีบัญชี? ',
                              style: TextStyle(color: Colors.grey)),
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
          },
        ),
      ),
    );
  }
}