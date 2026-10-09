// เทส FirestoreService.deleteCycleLog — ลบ log แล้ว log ถัดไปต้องได้
// usedFromLast ใหม่ที่ส่งมา ในการเขียนครั้งเดียวกัน
import 'package:energy_home/models/water_log_model.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = FirestoreService(firestore: firestore);
    // ต้นรอบ 100 → จด 110, 125, 140
    for (final (id, day, value, fromStart, fromLast) in [
      ('a', 5, 110.0, 10.0, 10.0),
      ('b', 10, 125.0, 25.0, 15.0),
      ('c', 15, 140.0, 40.0, 15.0),
    ]) {
      await service.saveWaterLog(WaterLogModel(
          id: id, uid: 'u', date: DateTime(2026, 6, day), meterValue: value,
          usedFromStart: fromStart, usedFromLast: fromLast));
    }
  });

  Future<Map<String, dynamic>?> doc(String id) async =>
      (await firestore.collection('users/u/water_logs').doc(id).get()).data();

  test('ลบ log ตรงกลาง: log ถัดไปนับเพิ่มจาก log ก่อนหน้าแทน', () async {
    await service.deleteCycleLog('u', 'b',
        isWater: true, nextLogId: 'c', nextUsedFromLast: 30);
    expect(await doc('b'), isNull);
    expect((await doc('c'))!['usedFromLast'], 30);
    expect((await doc('a'))!['usedFromLast'], 10);
  });

  test('ลบ log ล่าสุด: ไม่แตะ log อื่น', () async {
    await service.deleteCycleLog('u', 'c', isWater: true);
    expect(await doc('c'), isNull);
    expect((await doc('b'))!['usedFromLast'], 15);
  });
}
