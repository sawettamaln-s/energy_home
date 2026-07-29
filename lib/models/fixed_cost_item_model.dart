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

  FixedCostItemModel({
    required this.id,
    required this.uid,
    required this.name,
    required this.category,
    required this.amount,
    required this.createdAt,
  });

  factory FixedCostItemModel.fromMap(Map<String, dynamic> map) {
    return FixedCostItemModel(
      id: map['id'] ?? '',
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? 'other',
      amount: (map['amount'] ?? 0).toDouble(),
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
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
    };
  }
}