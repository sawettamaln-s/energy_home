import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// รวม logic เข้าสู่ระบบ/สมัครสมาชิกด้วย Google ไว้ที่เดียว ใช้ร่วมกันทั้ง
/// LoginScreen และ RegisterScreen — ฝั่ง Firebase แล้ว signInWithCredential
/// ทำหน้าที่ทั้ง sign-in และ sign-up ในตัวเดียว (ถ้าเป็นบัญชี Google ที่ไม่เคย
/// สมัครมาก่อน Firebase จะสร้าง user ให้อัตโนมัติ แล้ว AuthGate ที่ฟัง
/// authStateChanges() อยู่แล้วจะพาไปหน้า Setup ต่อเองเหมือนสมัครด้วยอีเมล)
///
/// ใช้ package google_sign_in เวอร์ชัน 7.x — ต้องเรียก initialize() ก่อน
/// ครั้งแรก แล้วค่อยเรียก authenticate() (ไม่มีเมธอด signIn() ตรงๆ)
class GoogleAuthService {
  GoogleAuthService._();

  // Web Client ID (ประเภท OAuth 2.0 "Web client (auto created by Google
  // Service)") ที่ Firebase สร้างให้อัตโนมัติตอนเปิดใช้งาน Google เป็น
  // Sign-in provider — คัดลอกได้จาก:
  // Firebase Console > Authentication > Sign-in method > Google
  //   > Web SDK configuration > Web client ID
  // หรือจากไฟล์ google-services.json (android/app/) ที่ field
  // client_type: 3 ภายใต้ oauth_client
  //
  // ต้องเป็น serverClientId (ไม่ใช่ Android client ID) ต่อให้แอปนี้เป็น
  // Android-only ก็ตาม เพราะ Firebase ต้องใช้ id_token ที่ออกโดย Web client
  // ตัวนี้ในการแลก credential ฝั่ง Firebase Auth
  static const String _serverClientId =
      '382287446671-3ddv1vbj4d4psqcpiitjj0sjg3rvn54k.apps.googleusercontent.com';

  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
    _initialized = true;
  }

  /// เปิดหน้าต่างเลือกบัญชี Google แล้ว sign in เข้า Firebase ให้
  /// คืนค่า UserCredential เมื่อสำเร็จ, null เมื่อผู้ใช้กดยกเลิกเอง (ไม่ throw
  /// กรณียกเลิก เพื่อให้ผู้เรียกไม่ต้องแยกเช็ค exception code เอง)
  static Future<UserCredential?> signIn() async {
    await _ensureInitialized();

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  }
}