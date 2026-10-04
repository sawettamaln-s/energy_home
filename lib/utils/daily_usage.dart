// =====================================================================
// การใช้รายวันของรอบบิล — แปลง log ที่เป็นยอดสะสมตั้งแต่ต้นรอบ
// (usedFromStart) เป็นหน่วยที่ใช้ "ต่อวัน" ให้กราฟรายวันบนหน้าหลัก
//
// ผู้ใช้ไม่ได้จดทุกวัน หน่วยที่เพิ่มขึ้นระหว่างการจด 2 ครั้งจึงเฉลี่ยลงทุกวัน
// ในช่วงนั้นเท่าๆ กัน: จดวันที่ a แล้วจดอีกทีวันที่ b หน่วยที่เพิ่มแบ่งให้วัน
// a+1 ถึง b ส่วนช่วงแรกนับจากเลขมิเตอร์ต้นรอบ (ยอด 0) ครอบวันแรกของรอบด้วย
// จดหลายครั้งในวันเดียวกันรวมเป็นของวันนั้น วันหลังการจดครั้งล่าสุดยังไม่มี
// ข้อมูล (null)
// =====================================================================
class DailyUsage {
  // [readings] = (วันที่จด, ยอดสะสมตั้งแต่ต้นรอบ) ลำดับไหนก็ได้
  // คืนลิสต์ยาว [cycleDays] ช่อง ช่องที่ i = หน่วยที่ใช้ในวันที่ i ของรอบ
  static List<double?> spread({
    required DateTime cycleStart,
    required int cycleDays,
    required List<(DateTime, double)> readings,
  }) {
    final values = List<double?>.filled(cycleDays, null);
    if (cycleDays <= 0) return values;
    final sorted = [...readings]..sort((a, b) => a.$1.compareTo(b.$1));

    var prevIndex = -1;
    var prevUsed = 0.0;
    for (final (date, used) in sorted) {
      final index = _dayIndex(cycleStart, date).clamp(0, cycleDays - 1);
      final delta = used > prevUsed ? used - prevUsed : 0.0;
      if (index <= prevIndex) {
        // จดซ้ำวันเดิม (หรือวันที่ย้อนหลังวันที่จดก่อนหน้า) รวมเป็นของวันนั้น
        final target = prevIndex < 0 ? 0 : prevIndex;
        values[target] = (values[target] ?? 0) + delta;
      } else {
        final perDay = delta / (index - prevIndex);
        for (var i = prevIndex + 1; i <= index; i++) {
          values[i] = (values[i] ?? 0) + perDay;
        }
        prevIndex = index;
      }
      if (used > prevUsed) prevUsed = used;
    }
    return values;
  }

  // วันที่ของรอบ (0 = วันตัดรอบ) นับตามปฏิทิน ไม่สนเวลาในวัน
  static int _dayIndex(DateTime cycleStart, DateTime date) {
    final start = DateTime(cycleStart.year, cycleStart.month, cycleStart.day);
    final day = DateTime(date.year, date.month, date.day);
    return (day.difference(start).inHours / 24).round();
  }
}
