import 'package:flutter/foundation.dart';

/// บัสกลางง่ายๆ ไว้แจ้งเตือน "ข้อมูลเปลี่ยนแล้ว ให้โหลดใหม่" ข้ามแท็บ
///
/// จำเป็นเพราะ MainShell ใช้ IndexedStack เก็บทุกแท็บไว้ตลอดอายุแอป (ดู
/// comment ใน main_shell.dart) ทำให้ initState ของแต่ละหน้าไม่รันซ้ำตอน
/// สลับแท็บ — เวลามีการแก้ไข/ลบข้อมูลจากแท็บอื่น (เช่น ลบ log มิเตอร์,
/// ล้าง/ตั้งค่ามิเตอร์ต้นรอบ, แก้บิลย้อนหลัง ที่แท็บ "ตั้งค่า") หน้า
/// Dashboard ที่ค้างอยู่ใน IndexedStack จะไม่รู้เลยว่าข้อมูลเปลี่ยน
/// ถ้าไม่มีตัวกลางนี้คอยบอก
///
/// วิธีใช้: FirestoreService เรียก DataRefreshBus.instance.notifyChanged()
/// ทุกครั้งหลังเขียน/ลบข้อมูลที่หน้าอื่นอาจต้องรู้ ฝั่งหน้าที่ต้อง auto
/// refresh (เช่น DashboardScreen) ก็ addListener กับ
/// DataRefreshBus.instance.version ใน initState แล้วเรียกโหลดข้อมูลใหม่
/// ทุกครั้งที่ค่าเปลี่ยน (อย่าลืม removeListener ใน dispose)
class DataRefreshBus {
  DataRefreshBus._();
  static final DataRefreshBus instance = DataRefreshBus._();

  final ValueNotifier<int> version = ValueNotifier<int>(0);

  void notifyChanged() {
    version.value++;
  }
}