/// รายการค่าใช้จ่ายคงที่ (Fixed Cost) แต่ละตัว เช่น ค่าแก๊สหุงต้ม,
/// ค่าอินเทอร์เน็ตบ้าน, ค่าส่วนกลาง ฯลฯ
///
/// เก็บแยกเป็นรายการย่อยใน subcollection `fixed_costs` ของ user แต่ละคน
/// (เหมือนแพทเทิร์นเดียวกับ start_meter_history) แทนที่จะเก็บเป็นยอดรวม
/// ตัวเดียวแบบเดิม ส่วนยอดรวม (`UserModel.fixedCost`) ยังเก็บ cache ไว้ที่
/// users/{uid} เหมือนเดิม เพื่อให้โค้ดเดิมที่ใช้ user.fixedCost อยู่แล้ว
/// (Dashboard, compileBill) ทำงานต่อได้โดยไม่ต้องแก้ที่อื่น — ดูการ sync ยอด
/// รวมที่ FirestoreService._recalcFixedCostTotal()
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