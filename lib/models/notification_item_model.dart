/// ===========================================================
/// NotificationItem
/// โมเดลข้อมูลแจ้งเตือน 1 รายการที่เคยถูกยิงไปแล้ว เก็บไว้แสดงใน
/// หน้า Notification Center (เพราะ flutter_local_notifications
/// ไม่มี history ในตัว ต้องบันทึกเองตอนยิงแต่ละครั้ง)
/// ===========================================================
class NotificationItem {
  final String id; // unique ต่อรายการ (ไม่ใช่ id ของ plugin)
  final String title;
  final String body;
  final String type; // 'billing' | 'meter' | 'spike' | 'summary' | 'welcome' | 'forecast'
  final DateTime timestamp;
  final bool isRead;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.isRead = false,
  });

  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      title: title,
      body: body,
      type: type,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory NotificationItem.fromMap(Map<String, dynamic> map) {
    return NotificationItem(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      type: map['type'] ?? 'meter',
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      isRead: map['isRead'] ?? false,
    );
  }
}