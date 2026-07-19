// เทสยืนยัน logic ของ StartMeterValidation (lib/widgets/start_meter_fields.dart)
// เป็น static function ล้วนๆ ไม่พึ่ง Firebase/widget เลย รันเร็ว มั่นใจสูง —
// เน้นเช็คว่า TOU กับมิเตอร์ปกติให้ผลลัพธ์ "เหมือนกันเชิงพฤติกรรม" ตามที่ควร
// เป็น (ต่างแค่วิธีกรอก ไม่ต่างที่ผลลัพธ์สุดท้ายว่า save ได้ไหม) รวมถึงเคส
// noBillYet และ isFirstEntry ที่เป็นจุดซับซ้อนสุดของฟอร์มนี้
import 'package:energy_home/widgets/start_meter_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseNumInput', () {
    test('ตัด comma คั่นหลักพันออกก่อน parse', () {
      expect(parseNumInput('8,500'), 8500);
      expect(parseNumInput('1,234,567.89'), 1234567.89);
    });

    test('มีช่องว่างหัวท้ายก็ยัง parse ได้', () {
      expect(parseNumInput('  120  '), 120);
    });

    test('parse ไม่ได้ (ข้อความว่าง/ไม่ใช่ตัวเลข) ต้องได้ 0 ไม่ใช่ error', () {
      expect(parseNumInput(''), 0);
      expect(parseNumInput('abc'), 0);
    });
  });

  group('electricityMeterOk — TOU ต้องพฤติกรรมเทียบเท่าปกติ', () {
    test('ปกติ: กรอกมิเตอร์ > 0 ถือว่า ok', () {
      expect(
        StartMeterValidation.electricityMeterOk(
            isTou: false, eVal: 100, peakVal: 0, offPeakVal: 0),
        isTrue,
      );
    });

    test('ปกติ: มิเตอร์ = 0 ถือว่ายังไม่ ok', () {
      expect(
        StartMeterValidation.electricityMeterOk(
            isTou: false, eVal: 0, peakVal: 0, offPeakVal: 0),
        isFalse,
      );
    });

    test('TOU: ต้องกรอกทั้ง Peak และ Off-Peak ถึงจะ ok (กรอกครึ่งเดียวไม่พอ)',
        () {
      expect(
        StartMeterValidation.electricityMeterOk(
            isTou: true, eVal: 0, peakVal: 100, offPeakVal: 0),
        isFalse,
        reason: 'มี Peak อย่างเดียวยังไม่ครบคู่',
      );
      expect(
        StartMeterValidation.electricityMeterOk(
            isTou: true, eVal: 0, peakVal: 0, offPeakVal: 50),
        isFalse,
        reason: 'มี Off-Peak อย่างเดียวยังไม่ครบคู่',
      );
      expect(
        StartMeterValidation.electricityMeterOk(
            isTou: true, eVal: 0, peakVal: 100, offPeakVal: 50),
        isTrue,
        reason: 'ครบทั้งคู่แล้วถึง ok — สมมาตรกับปกติที่ต้องมีค่า > 0',
      );
    });
  });

  group('electricityComplete — noBillYet ยกเว้นแค่เรื่องค่าใช้จ่าย', () {
    test('ปกติ: มีมิเตอร์แต่ยังไม่มีค่าใช้จ่ายและไม่ติ๊ก noBillYet -> ไม่ครบ',
        () {
      expect(
        StartMeterValidation.electricityComplete(
          isTou: false,
          eVal: 100,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 0,
          eNoBillYet: false,
        ),
        isFalse,
      );
    });

    test('ปกติ: ติ๊ก noBillYet แล้วไม่ต้องมีค่าใช้จ่ายก็ครบได้', () {
      expect(
        StartMeterValidation.electricityComplete(
          isTou: false,
          eVal: 100,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 0,
          eNoBillYet: true,
        ),
        isTrue,
      );
    });

    test('TOU: กติกา noBillYet เดียวกับปกติเป๊ะ (สมมาตร)', () {
      expect(
        StartMeterValidation.electricityComplete(
          isTou: true,
          eVal: 0,
          peakVal: 100,
          offPeakVal: 50,
          eCost: 0,
          eNoBillYet: true,
        ),
        isTrue,
      );
      expect(
        StartMeterValidation.electricityComplete(
          isTou: true,
          eVal: 0,
          peakVal: 100,
          offPeakVal: 50,
          eCost: 0,
          eNoBillYet: false,
        ),
        isFalse,
      );
    });

    test('isFirstEntry=true แต่ eUsed<=0 -> ไม่ครบ ไม่ว่า TOU หรือปกติ', () {
      expect(
        StartMeterValidation.electricityComplete(
          isTou: false,
          eVal: 100,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 500,
          eNoBillYet: false,
          isFirstEntry: true,
          eUsed: 0,
        ),
        isFalse,
      );
      expect(
        StartMeterValidation.electricityComplete(
          isTou: true,
          eVal: 0,
          peakVal: 100,
          offPeakVal: 50,
          eCost: 500,
          eNoBillYet: false,
          isFirstEntry: true,
          eUsed: 0,
        ),
        isFalse,
      );
    });

    test('isFirstEntry=true และ eUsed>0 -> ครบ (TOU/ปกติเหมือนกัน)', () {
      expect(
        StartMeterValidation.electricityComplete(
          isTou: false,
          eVal: 100,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 500,
          eNoBillYet: false,
          isFirstEntry: true,
          eUsed: 30,
        ),
        isTrue,
      );
      expect(
        StartMeterValidation.electricityComplete(
          isTou: true,
          eVal: 0,
          peakVal: 100,
          offPeakVal: 50,
          eCost: 500,
          eNoBillYet: false,
          isFirstEntry: true,
          eUsed: 30,
        ),
        isTrue,
      );
    });
  });

  group('electricityPartial — กรอกครึ่งเดียวต้องโดนจับได้ทั้ง TOU และปกติ',
      () {
    test('ปกติ: กรอกมิเตอร์แต่ไม่กรอกค่าใช้จ่าย (ไม่ติ๊ก noBillYet) = partial',
        () {
      expect(
        StartMeterValidation.electricityPartial(
          isTou: false,
          eVal: 100,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 0,
          eNoBillYet: false,
        ),
        isTrue,
      );
    });

    test('TOU: กรอกแค่ Peak (Off-Peak ว่าง) ต้องนับว่า partial เหมือนกัน', () {
      expect(
        StartMeterValidation.electricityPartial(
          isTou: true,
          eVal: 0,
          peakVal: 100,
          offPeakVal: 0,
          eCost: 500,
          eNoBillYet: false,
        ),
        isTrue,
        reason: 'มี Peak (touched) แต่ยังไม่ complete (ขาด Off-Peak) = partial',
      );
    });

    test('ไม่กรอกอะไรเลยทั้งคู่ -> ไม่ partial (ถือว่างเปล่า ไม่ใช่กรอกครึ่ง)',
        () {
      expect(
        StartMeterValidation.electricityPartial(
          isTou: true,
          eVal: 0,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 0,
          eNoBillYet: false,
        ),
        isFalse,
      );
    });
  });

  group('waterComplete/waterPartial', () {
    test('มีมิเตอร์น้ำแต่ไม่มีค่าใช้จ่ายและไม่ติ๊ก noBillYet -> ไม่ครบ', () {
      expect(
        StartMeterValidation.waterComplete(
            wVal: 50, wCost: 0, wNoBillYet: false),
        isFalse,
      );
    });

    test('ติ๊ก noBillYet แล้วครบได้โดยไม่ต้องมีค่าใช้จ่าย', () {
      expect(
        StartMeterValidation.waterComplete(
            wVal: 50, wCost: 0, wNoBillYet: true),
        isTrue,
      );
    });

    test('isFirstEntry=true แต่ wUsed<=0 -> ไม่ครบ', () {
      expect(
        StartMeterValidation.waterComplete(
          wVal: 50,
          wCost: 200,
          wNoBillYet: false,
          isFirstEntry: true,
          wUsed: 0,
        ),
        isFalse,
      );
    });
  });

  group('canSave — เคสรวมที่ผู้ใช้จริงจะเจอ', () {
    test('ไม่กรอกอะไรเลย -> save ไม่ได้', () {
      expect(
        StartMeterValidation.canSave(
          isTou: false,
          eVal: 0,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 0,
          wVal: 0,
          wCost: 0,
          eNoBillYet: false,
          wNoBillYet: false,
        ),
        isFalse,
      );
    });

    test('กรอกแค่ไฟฟ้าครบ (น้ำเว้นว่างทั้งคู่) -> save ได้ (มีบิลแค่ฝั่งเดียว)',
        () {
      expect(
        StartMeterValidation.canSave(
          isTou: false,
          eVal: 14000,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 1500,
          wVal: 0,
          wCost: 0,
          eNoBillYet: false,
          wNoBillYet: false,
        ),
        isTrue,
      );
    });

    test('กรอกไฟฟ้าครบแต่กรอกน้ำครึ่งเดียว (มีมิเตอร์น้ำแต่ไม่มีค่าใช้จ่าย) '
        '-> save ไม่ได้ ทั้งที่ไฟฟ้าครบแล้ว', () {
      expect(
        StartMeterValidation.canSave(
          isTou: false,
          eVal: 14000,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 1500,
          wVal: 50, // กรอกมิเตอร์น้ำ
          wCost: 0, // แต่ไม่กรอกค่าน้ำ ไม่ติ๊ก noBillYet
          eNoBillYet: false,
          wNoBillYet: false,
        ),
        isFalse,
        reason: 'กันไม่ให้ข้อมูลน้ำครึ่งๆ กลางๆ หลุดเข้าไปในระบบ',
      );
    });

    test('TOU: กรอกไฟฟ้าครบคู่ (Peak+OffPeak) เทียบเท่าปกติกรอกมิเตอร์เดียว',
        () {
      expect(
        StartMeterValidation.canSave(
          isTou: true,
          eVal: 0,
          peakVal: 9000,
          offPeakVal: 5000,
          eCost: 1500,
          wVal: 0,
          wCost: 0,
          eNoBillYet: false,
          wNoBillYet: false,
        ),
        isTrue,
      );
    });

    test('TOU: กรอกแค่ Peak (ขาด Off-Peak) -> save ไม่ได้ (parity กับปกติ '
        'ที่กรอกมิเตอร์ครึ่งเดียวไม่ได้เหมือนกัน)', () {
      expect(
        StartMeterValidation.canSave(
          isTou: true,
          eVal: 0,
          peakVal: 9000,
          offPeakVal: 0,
          eCost: 1500,
          wVal: 0,
          wCost: 0,
          eNoBillYet: false,
          wNoBillYet: false,
        ),
        isFalse,
      );
    });

    test('เป็นการตั้งค่าครั้งแรก (isFirstEntry) แต่ลืมกรอกหน่วยที่ใช้ไป '
        '-> save ไม่ได้ ทั้ง TOU และปกติ', () {
      expect(
        StartMeterValidation.canSave(
          isTou: false,
          eVal: 14000,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 1500,
          wVal: 0,
          wCost: 0,
          eNoBillYet: false,
          wNoBillYet: false,
          eIsFirstEntry: true,
          eUsed: 0,
        ),
        isFalse,
      );
      expect(
        StartMeterValidation.canSave(
          isTou: true,
          eVal: 0,
          peakVal: 9000,
          offPeakVal: 5000,
          eCost: 1500,
          wVal: 0,
          wCost: 0,
          eNoBillYet: false,
          wNoBillYet: false,
          eIsFirstEntry: true,
          eUsed: 0,
        ),
        isFalse,
      );
    });

    test('ติ๊ก noBillYet ทั้งไฟและน้ำ กรอกแค่มิเตอร์ -> save ได้ทั้งคู่', () {
      expect(
        StartMeterValidation.canSave(
          isTou: false,
          eVal: 14000,
          peakVal: 0,
          offPeakVal: 0,
          eCost: 0,
          wVal: 50,
          wCost: 0,
          eNoBillYet: true,
          wNoBillYet: true,
        ),
        isTrue,
      );
    });
  });
}