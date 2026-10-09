# เทส Firestore security rules

เทส `firestore.rules` (ที่ root ของโปรเจกต์) บน Firestore emulator ว่า

- ทุกรูปแบบข้อมูลที่แอปเขียนจริงผ่าน (ทุกโมเดล, การแก้ข้อมูลผู้ใช้บางฟิลด์, batch ตอนคิด log ใหม่/ลบ log)
- เอกสารเก่าที่มีค่าแปลกยังแก้ฟิลด์อื่นได้ (กฎตรวจเฉพาะฟิลด์ที่เปลี่ยน)
- คนอื่นและผู้ที่ไม่ได้ login อ่าน/เขียนไม่ได้, คอลเลกชันย่อยที่ไม่รู้จักถูกปฏิเสธ, ค่า Ft อ่านได้อย่างเดียว
- ข้อมูลผิด (ติดลบ, ผิดชนิด, ค่านอกชุดที่กำหนด, id/uid ไม่ตรง path, ฟิลด์เกิน) ถูกปฏิเสธ

ไม่อยู่ใน CI และไม่รันด้วย `flutter test` ให้รันเองทุกครั้งที่แก้ `firestore.rules`
หรือเพิ่มฟิลด์/คอลเลกชันใหม่ในแอป

## ต้องมี

- Node.js 18 ขึ้นไป
- Firebase CLI (`npm install -g firebase-tools`)
- Java 21 ขึ้นไป (emulator ของ Firebase CLI รุ่นปัจจุบันไม่รองรับรุ่นต่ำกว่านี้)

## วิธีรัน

```bash
cd test/firestore_rules
npm install
npm test
```

`npm test` เปิด Firestore emulator (โปรเจกต์ `demo-energy-home` ไม่แตะ Firebase จริง)
รันเทส แล้วปิด emulator เอง ถ้า Java ในเครื่องต่ำกว่า 21 ให้ตั้ง `JAVA_HOME` ชี้ไปที่ JDK 21 ก่อนรัน
