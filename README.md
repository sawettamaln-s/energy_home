# Energy Home

แอปมือถือ (Flutter) สำหรับติดตามการใช้ไฟฟ้าและน้ำประปาภายในบ้าน บันทึกเลขมิเตอร์รายวัน
คำนวณค่าใช้จ่ายโดยประมาณ และวิเคราะห์แนวโน้มการใช้งานย้อนหลัง

## ฟีเจอร์หลัก

- **บันทึกมิเตอร์** — บันทึกเลขมิเตอร์ไฟฟ้า (รองรับทั้งมิเตอร์ปกติและมิเตอร์ TOU
  แยก On-Peak/Off-Peak) และมิเตอร์น้ำประปา พร้อมคำนวณค่าใช้จ่ายโดยประมาณจาก
  โครงสร้างอัตราจริงของ MEA/PEA/MWA/PWA
- **แดชบอร์ด** — สรุปสถานะรอบบิลปัจจุบัน (ผ่านมากี่วัน เหลืออีกกี่วัน) และ
  ประมาณการค่าใช้จ่ายก่อนสิ้นรอบ
- **วิเคราะห์แนวโน้ม** — กราฟเปรียบเทียบการใช้งานรายเดือน พร้อมคาดการณ์เดือน
  ถัดไปด้วยวิธี seasonal curve (ถ้ามีข้อมูลพอ) หรือ linear regression (fallback)
- **ค่าใช้จ่ายคงที่** — บันทึกรายการค่าใช้จ่ายประจำ (เช่น ค่าเน็ต, ค่าประกัน)
  ที่คิดรวมเข้าไปในบิลแต่ละรอบตามช่วงวันที่ที่ใช้งานจริง
- **ประวัติการบันทึก** — ดูย้อนหลังการบันทึกมิเตอร์และบิลแต่ละเดือน
- **แจ้งเตือน** — เตือนก่อนถึงวันตัดรอบบิล

## สถาปัตยกรรม

```
lib/
├── models/       ข้อมูล (BillModel, UserModel, ElectricityLogModel, ...)
├── screens/      หน้าจอ แบ่งตามฟีเจอร์ (dashboard, analysis, appliance, settings, auth)
├── services/     ตัวเชื่อมต่อ Firestore, การคำนวณ/วิเคราะห์, การแจ้งเตือน
├── utils/        ตรรกะล้วน ไม่พึ่ง Firebase/widget (คำนวณรอบบิล, คาดการณ์, วันที่ไทย)
└── widgets/      widget ที่ใช้ร่วมกันหลายหน้าจอ (AppTopBar, BillMockupCard, ...)
```

- ข้อมูลเก็บใน **Firebase Firestore** ผ่าน `FirestoreService` ซึ่งรับ
  `FirebaseFirestore` instance แบบ dependency injection ได้ (ใช้
  `fake_cloud_firestore` แทนของจริงตอนเทส)
- Login ผ่าน Firebase Auth (อีเมล/รหัสผ่าน และ Google Sign-In)
- `EnergyForecaster` (ใน `lib/utils/forecaster.dart`) รวมตรรกะเรื่องขอบเขตรอบบิล
  และการคาดการณ์ไว้เป็นแหล่งความจริงเดียว ไม่ให้แต่ละหน้าจอคำนวณเองแยกกัน

## เริ่มต้นใช้งาน (Development)

ต้องมี [Flutter SDK](https://docs.flutter.dev/get-started/install) และบัญชี
Firebase ของตัวเอง (ไฟล์ `lib/firebase_options.dart` และ
`android/app/google-services.json` ผูกกับโปรเจกต์ Firebase ส่วนตัวของผู้พัฒนา
จึงไม่รวมอยู่ใน repo — สร้างโปรเจกต์ Firebase ของตัวเองแล้วรัน
`flutterfire configure` เพื่อ generate `lib/firebase_options.dart` ของจริง
หรือจะคัดลอก `lib/firebase_options.sample.dart` ไปเป็น `lib/firebase_options.dart`
แล้วใส่ค่าจริงเองก็ได้)

```bash
flutter pub get
flutter run
```

## รันเทส

โปรเจกต์นี้มีชุดเทสอัตโนมัติอยู่ใน `test/` ครอบคลุมตรรกะสำคัญ (การคำนวณบิล,
migration, validation ของฟอร์ม, และ auth routing) โดยใช้ `fake_cloud_firestore`
และ `firebase_auth_mocks` แทนของจริง จึงรันได้โดยไม่ต้องต่อ Firebase จริง:

```bash
flutter test
```

ตรวจสไตล์โค้ด:

```bash
flutter analyze
```

## หมายเหตุ

- `FirestoreService.migrateTouCompiledBills()` เป็นเครื่องมือแก้ข้อมูลย้อนหลัง
  แบบครั้งเดียว (one-off) สำหรับบั๊กเก่าที่แก้ไปแล้วใน `compileBill()` —
  ตั้งใจไม่มีปุ่มเรียกใช้ใน UI เพราะเป็นงานแอดมิน ไม่ใช่ฟีเจอร์ผู้ใช้ทั่วไป
  (ดูรายละเอียดและเงื่อนไขการใช้งานในคอมเมนต์เหนือฟังก์ชัน และเทสที่ครอบไว้ใน
  `test/migrate_tou_compiled_bills_test.dart`)
- โปรเจกต์นี้เป็นงานส่วนตัว/โปรเจกต์การศึกษา ยังพัฒนาต่อเนื่องอยู่