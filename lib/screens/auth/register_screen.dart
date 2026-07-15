import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

      // กลับไปหน้า Login
      if (mounted) {
        Navigator.pop(context);
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'สมัครสมาชิก',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ช่องชื่อ
              const Text('ชื่อ-นามสกุล',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: _fieldDecoration(
                  hint: 'กรอกชื่อของคุณ',
                  icon: Icons.person_outlined,
                ),
              ),

              const SizedBox(height: 16),

              // ช่อง Email
              const Text('อีเมล',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _fieldDecoration(
                  hint: 'example@email.com',
                  icon: Icons.email_outlined,
                ),
              ),

              const SizedBox(height: 16),

              // ช่อง Password
              const Text('รหัสผ่าน',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: _fieldDecoration(
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
              const Text('ยืนยันรหัสผ่าน',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: _fieldDecoration(
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
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ปุ่มสมัคร
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('สมัครสมาชิก',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // สไตล์ช่องกรอกกลาง — พื้นเทาอ่อนไม่มีเส้นขอบ ให้เป็นชุดเดียวกับหน้า login
  InputDecoration _fieldDecoration({
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
      ),
    );
  }
}