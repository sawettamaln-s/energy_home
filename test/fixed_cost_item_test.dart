import 'package:energy_home/models/fixed_cost_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FixedCostItemModel.isActiveInMonth', () {
    // สถานการณ์: user เพิ่มรายการกลางเดือน มิ.ย. (เช่น 15 มิ.ย.)
    // แล้วมาตั้งวันสิ้นสุดกลางเดือน ก.ค. ถัดมา (เช่น 10 ก.ค.)
    final item = FixedCostItemModel(
      id: 'test-1',
      uid: 'user-1',
      name: 'ค่าเน็ตบ้าน',
      category: 'internet',
      amount: 500,
      createdAt: DateTime(2026, 6, 15),
      startDate: DateTime(2026, 6, 15),
      endDate: DateTime(2026, 7, 10),
    );

    test('เดือนก่อนเริ่ม (พ.ค.) ต้องไม่ active', () {
      expect(item.isActiveInMonth(DateTime(2026, 5, 1)), false);
    });

    test('เดือนที่เริ่ม (มิ.ย.) ต้อง active แม้เริ่มกลางเดือน', () {
      expect(item.isActiveInMonth(DateTime(2026, 6, 1)), true);
    });

    test(
        'เดือนที่ตั้ง endDate ไว้ (ก.ค.) ต้องยัง active ทั้งเดือน '
        '(เทียบระดับเดือน ไม่ใช่วันที่ตรงเป๊ะ — known limitation ที่ตั้งใจ)',
        () {
      expect(item.isActiveInMonth(DateTime(2026, 7, 1)), true);
      expect(item.isActiveInMonth(DateTime(2026, 7, 31)), true);
    });

    test('เดือนถัดจาก endDate (ส.ค.) ต้องไม่ active แล้ว', () {
      expect(item.isActiveInMonth(DateTime(2026, 8, 1)), false);
    });

    test('endDate = null (ไม่มีกำหนดสิ้นสุด) ต้อง active ตลอดไปในอนาคต', () {
      final ongoing = FixedCostItemModel(
        id: 'test-2',
        uid: 'user-1',
        name: 'ค่าประกันบ้าน',
        category: 'insurance',
        amount: 300,
        createdAt: DateTime(2026, 6, 15),
      );
      expect(ongoing.isActiveInMonth(DateTime(2027, 1, 1)), true);
    });
  });

  group('Badge "หมดอายุแล้ว" (isExpired ใน settings_fixed_cost.dart)', () {
    // isExpired = item.endDate != null && !item.isActiveInMonth(DateTime.now())
    // เทสต์นี้จำลอง logic เดียวกันตรงๆ เพื่อยืนยันจังหวะที่ badge ควรขึ้น
    bool isExpired(FixedCostItemModel item, DateTime now) =>
        item.endDate != null && !item.isActiveInMonth(now);

    final item = FixedCostItemModel(
      id: 'test-3',
      uid: 'user-1',
      name: 'ค่าเน็ตบ้าน',
      category: 'internet',
      amount: 500,
      createdAt: DateTime(2026, 6, 15),
      startDate: DateTime(2026, 6, 15),
      endDate: DateTime(2026, 7, 10),
    );

    test('ยังไม่ขึ้น badge ตลอดเดือน ก.ค. (เดือนที่ endDate ตกอยู่)', () {
      expect(isExpired(item, DateTime(2026, 7, 20)), false);
    });

    test('ขึ้น badge ทันทีที่เข้าเดือน ส.ค.', () {
      expect(isExpired(item, DateTime(2026, 8, 1)), true);
    });
  });
}