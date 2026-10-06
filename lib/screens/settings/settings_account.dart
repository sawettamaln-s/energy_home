part of 'settings_screen.dart';

// ==================== ลบบัญชี + ข้อมูลทั้งหมด (PDPA) ====================
// ลำดับ: 1) ยืนยัน+อธิบายผล 2) reauthenticate (Firebase บังคับ
// requires-recent-login สำหรับ operation อ่อนไหวแบบนี้) — บัญชีอีเมลขอรหัสผ่าน,
// บัญชี Google ล้วนไม่มีรหัสผ่าน จึงให้เลือกบัญชี Google ยืนยันซ้ำแทน
// 3) ลบข้อมูลใน Firestore
// ก่อนแล้วค่อยลบบัญชี Auth ทีหลังสุด (สลับลำดับแล้วลบ Firestore ไม่สำเร็จ
// จะไม่มีทาง sign-in กลับมาลบข้อมูลที่เหลือได้อีก)
// [setBusy] = บอกหน้าตั้งค่าให้แสดง/ซ่อนวงหมุนระหว่างลบ
Future<void> _confirmDeleteAccount(
  BuildContext context, {
  required FirestoreService firestoreService,
  required void Function(bool busy) setBusy,
}) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'ลบบัญชีและข้อมูลทั้งหมด?',
    content: 'การลบบัญชีจะลบข้อมูลทั้งหมดถาวร ได้แก่ ประวัติมิเตอร์ไฟ/น้ำ, '
        'บิลย้อนหลังทั้งหมด, เครื่องใช้ไฟฟ้าที่บันทึกไว้, รายจ่ายประจำ '
        'และการตั้งค่าบัญชีทั้งหมด — กู้คืนไม่ได้ไม่ว่ากรณีใดค่ะ',
    confirmLabel: 'ลบถาวร',
  );
  if (!confirmed) return;
  if (!context.mounted) return;

  final authUser = FirebaseAuth.instance.currentUser;
  if (authUser == null) return;
  final usesPassword =
      authUser.providerData.any((p) => p.providerId == 'password');

  AuthCredential? credential;
  try {
    credential = await _askReauthCredential(context, authUser, usesPassword);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('ยืนยันตัวตนด้วย Google ไม่สำเร็จ กรุณาลองใหม่อีกครั้งค่ะ')),
    );
    return;
  }
  // null = ผู้ใช้กดยกเลิกตอนยืนยันตัวตน
  if (credential == null) return;
  if (!context.mounted) return;

  setBusy(true);
  try {
    final user = FirebaseAuth.instance.currentUser!;
    await user.reauthenticateWithCredential(credential);

    await NotificationService.instance.cancelScheduledForSignOut();
    await firestoreService.deleteAllUserData(user.uid);
    await user.delete();

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthGate()),
      (route) => false,
    );
  } on FirebaseAuthException catch (e) {
    if (!context.mounted) return;
    setBusy(false);
    String message = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้งค่ะ';
    if (e.code == 'user-mismatch') {
      message = 'บัญชี Google ที่เลือกไม่ตรงกับบัญชีที่ใช้งานอยู่ค่ะ';
    } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
      message = usesPassword
          ? 'รหัสผ่านไม่ถูกต้องค่ะ'
          : 'ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่อีกครั้งค่ะ';
    } else if (e.code == 'too-many-requests') {
      message = 'ลองผิดหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่ค่ะ';
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  } catch (e) {
    if (!context.mounted) return;
    setBusy(false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('ลบบัญชีไม่สำเร็จ กรุณาลองใหม่อีกครั้งค่ะ')),
    );
  }
}

// ขอ credential สำหรับยืนยันตัวตนก่อนลบบัญชี — คืนค่า null ถ้ากดยกเลิก
// บัญชีที่มี provider 'password' → กรอกรหัสผ่าน / นอกนั้น (Google) → เลือกบัญชี Google
Future<AuthCredential?> _askReauthCredential(
    BuildContext context, User user, bool usesPassword) async {
  if (usesPassword) {
    final password = await _askPasswordForDeletion(context);
    if (password == null || password.isEmpty) return null;
    return EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
  }
  return GoogleAuthService.getCredential();
}

// ขอรหัสผ่านก่อนลบบัญชี — คืนค่า null ถ้ากดยกเลิก
Future<String?> _askPasswordForDeletion(BuildContext context) {
  final ctrl = TextEditingController();
  bool obscure = true;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v16)),
        title: const Text('ยืนยันตัวตนก่อนลบบัญชี',
            style: TextStyle(fontSize: AppTypography.s16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'กรอกรหัสผ่านของบัญชีนี้อีกครั้งเพื่อยืนยันว่าเป็นคุณเอง',
              style: TextStyle(fontSize: AppTypography.s13_5, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'รหัสผ่าน',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.v10)),
                suffixIcon: IconButton(
                  icon:
                      Icon(obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setDialogState(() => obscure = !obscure),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('ยืนยัน', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ),
  );
}
