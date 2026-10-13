// เทส AnalysisService.fetchBills — หน้าวิเคราะห์ต้องได้บิลครบทุกใบ หน้าประวัติ
// จึงรวมยอดรายปีของปีเก่าได้ครบทุกเดือน
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/services/analysis_service.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('บิล 30 ใบ -> ได้ครบ 30 ใบ เรียงเก่าไปใหม่', () async {
    final db = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: db);
    for (var i = 0; i < 30; i++) {
      final d = DateTime(2024, 1 + i, 1);
      await service.saveBill(BillModel(
          id: '${d.year}-${d.month}', uid: 'u', year: d.year, month: d.month, electricityCost: 1000));
    }

    final bills = await AnalysisService(firestore: db).fetchBills('u');

    expect(bills, hasLength(30));
    expect((bills.first.year, bills.first.month), (2024, 1));
    expect((bills.last.year, bills.last.month), (2026, 6));
  });

  test('ระบุ limitMonths -> ได้เฉพาะ N เดือนล่าสุด', () async {
    final db = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: db);
    for (var m = 1; m <= 12; m++) {
      await service.saveBill(BillModel(id: '2025-$m', uid: 'u', year: 2025, month: m, electricityCost: 1000));
    }

    final bills = await AnalysisService(firestore: db).fetchBills('u', limitMonths: 3);

    expect([for (final b in bills) b.month], [10, 11, 12]);
  });
}
