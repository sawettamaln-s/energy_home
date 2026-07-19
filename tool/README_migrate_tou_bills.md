# TOU bill migration — standalone script

พอร์ตมาจาก `FirestoreService.migrateTouCompiledBills()` ให้รันนอกแอปได้ผ่าน
`dart run` ตรงๆ (ไม่ต้อง `pub get` เพิ่มอะไร ใช้แค่ `dart:io`/`dart:convert`
ที่มากับ Dart SDK)

## วางไฟล์

คัดลอก `tool/migrate_tou_bills.dart` ไปไว้ในโฟลเดอร์ `tool/` ของ repo
(อยู่ระดับเดียวกับ `lib/`, `pubspec.yaml`)

## เตรียมของก่อนรัน

- **Firebase Web API Key**: Firebase Console > Project settings > General >
  Web API Key (อันเดียวกับที่อยู่ใน `firebase_options.dart` field `apiKey`
  ของแพลตฟอร์มไหนก็ได้)
- **Project ID**: อันเดียวกับ `projectId` ใน `firebase_options.dart`
- อีเมล/รหัสผ่านของบัญชี user ที่จะ migrate บิลให้ (security rules ส่วนใหญ่
  ผูก uid ของบิลกับ `request.auth.uid` ของคนที่ sign-in อยู่)

## ขั้นตอน

1. **Dry-run ก่อนเสมอ** (ค่า default ของสคริปต์):

   ```bash
   dart run tool/migrate_tou_bills.dart \
     --project-id=YOUR_PROJECT_ID \
     --api-key=YOUR_FIREBASE_WEB_API_KEY \
     --email=user@example.com
   ```

   จะถาม password แบบซ่อนตัวอักษร แล้วพิมพ์ตารางสรุปทุกบิลที่เป็น
   `source=compiled`: เดิม/ใหม่เท่าไหร่ บิลไหนจะเปลี่ยน บิลไหนข้ามเพราะอะไร
   — ยังไม่มีการเขียนข้อมูลใดๆ ในขั้นนี้

2. อ่าน preview ให้ครบ พอใจแล้วค่อยรันซ้ำพร้อม `--apply` (จะมีขั้นยืนยัน
   พิมพ์ `yes` ก่อนเขียนจริง หรือใส่ `--yes` ถ้ารันแบบ non-interactive):

   ```bash
   dart run tool/migrate_tou_bills.dart \
     --project-id=YOUR_PROJECT_ID \
     --api-key=YOUR_FIREBASE_WEB_API_KEY \
     --email=user@example.com \
     --apply
   ```

   ขั้นนี้จะอัปเดตเฉพาะ 2 ฟิลด์ (`electricityPeakUsed`,
   `electricityOffPeakUsed`) ของบิลที่ต้องแก้จริงๆ เท่านั้น — ปลอดภัยกว่า
   การเขียนทับทั้งเอกสารแบบต้นฉบับ เพราะไม่มีทางไปกระทบฟิลด์อื่นของบิล
   โดยไม่ตั้งใจ

3. งานเสร็จแล้วลบไฟล์ `tool/migrate_tou_bills.dart` (และไฟล์นี้) ทิ้งได้เลย
   ไม่ต้องเก็บไว้เป็นฟีเจอร์ถาวรของแอป

## ตรรกะ

ใช้สูตรและเงื่อนไขเดียวกับ `migrateTouCompiledBills()` ต้นฉบับทุกจุด
(เดินฐานมิเตอร์สะสมทีละรอบเป็นลูกโซ่, ข้ามรอบที่ log หายหรือไม่มีฐานตั้งต้น,
`dryRun=true` เป็นค่า default) — ถ้าจะแก้ตรรกะการคำนวณ ต้องแก้คู่กันทั้ง 2
ที่เพื่อไม่ให้ผลลัพธ์เพี้ยนไปจากที่แอปคำนวณจริง