// เทสการนับวันตั้งแต่จดมิเตอร์ล่าสุด (CurrentCycleForecast.daysSinceReading)
// ที่หน้าวิเคราะห์ใช้ตัดสินว่าจะบอกให้จดใหม่หรือไม่
import 'package:energy_home/services/analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

CurrentCycleForecast _cycle(DateTime? lastRecordedAt) => CurrentCycleForecast(
      currentCost: 171.84,
      forecastCost: 374.62,
      currentUnits: 43,
      forecastUnits: 102.93,
      daysElapsed: 15,
      remainingDays: 15,
      cycleLengthDays: 31,
      billMonth: DateTime(2026, 11, 1),
      projected: true,
      lastRecordedAt: lastRecordedAt,
    );

void main() {
  test('นับตามวันในปฏิทิน ไม่สนเวลา', () {
    final c = _cycle(DateTime(2026, 10, 24, 23, 50));
    expect(c.daysSinceReading(DateTime(2026, 10, 24, 23, 59)), 0);
    expect(c.daysSinceReading(DateTime(2026, 10, 25, 0, 5)), 1);
    expect(c.daysSinceReading(DateTime(2026, 10, 28, 9)), 4);
  });

  test('ข้ามเดือนได้', () {
    final c = _cycle(DateTime(2026, 10, 30, 12));
    expect(c.daysSinceReading(DateTime(2026, 11, 3, 8)), 4);
  });

  test('ยังไม่ได้จด -> null', () {
    expect(_cycle(null).daysSinceReading(DateTime(2026, 10, 24)), isNull);
  });
}
