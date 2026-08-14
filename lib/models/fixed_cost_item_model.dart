/// รายการค่าใช้จ่ายคงที่ 1 รายการ เช่น ค่าแก๊ส, ค่าเน็ตบ้าน, ค่าส่วนกลาง
///
/// เก็บเป็นรายการย่อยใน subcollection `fixed_costs` ของ user แต่ละคน
/// ส่วนยอดรวม (`UserModel.fixedCost`) จะถูก cache ไว้ที่ users/{uid}
/// และ sync อัตโนมัติทุกครั้งที่มีการแก้ไข ดูที่ FirestoreService._recalcFixedCostTotal()
class FixedCostItemModel {
  final String id;
  final String uid;
  final String name; // ชื่อที่โชว์ เช่น "ค่าแก๊สหุงต้ม"
  final String category; // key ไอคอน: gas/internet/maintenance/insurance/subscription/other
  final double amount; // บาทต่อเดือน
  final DateTime createdAt;
  final DateTime startDate; // เดือนที่เริ่มนับรวมในยอด fixed cost
  final DateTime? endDate; // null = ต่อเนื่องไม่มีกำหนดสิ้นสุด

  FixedCostItemModel({
    required this.id,
    required this.uid,
    required this.name,
    required this.category,
    required this.amount,
    required this.createdAt,
    DateTime? startDate,
    this.endDate,
  }) : startDate = startDate ?? createdAt;

  /// เช็คว่ารายการนี้ควรถูกนับรวมในยอด fixed cost ของเดือนที่ระบุไหม
  /// (เทียบแบบเหลื่อมเดือน ไม่ใช่เทียบวันที่ตรงเป๊ะ เพราะ fixed cost คิดเป็นรายเดือน)
  bool isActiveInMonth(DateTime month) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final started = !startDate.isAfter(monthEnd);
    final notEnded = endDate == null || !endDate!.isBefore(monthStart);
    return started && notEnded;
  }

  factory FixedCostItemModel.fromMap(Map<String, dynamic> map) {
    final createdAt =
        DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now();
    return FixedCostItemModel(
      id: map['id'] ?? '',
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? 'other',
      amount: (map['amount'] ?? 0).toDouble(),
      createdAt: createdAt,
      // รายการเก่าก่อนมี field นี้จะไม่มี startDate/endDate ใน Firestore เลย
      // → ตกกลับไปใช้ createdAt และ endDate = null (นับรวมต่อเนื่องเหมือนพฤติกรรมเดิม)
      startDate: DateTime.tryParse(map['startDate'] ?? '') ?? createdAt,
      endDate: map['endDate'] == null
          ? null
          : DateTime.tryParse(map['endDate']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'name': name,
      'category': category,
      'amount': amount,
      'createdAt': createdAt.toIso8601String(),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }
}