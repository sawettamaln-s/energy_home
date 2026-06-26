import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/notification_item_model.dart';
import '../../services/notification_service.dart';

/// ===========================================================
/// NotificationScreen
/// พาร์ทนี้ทำหน้าที่: หน้า "ศูนย์การแจ้งเตือน" แบบแอปทั่วไป —
/// แสดงประวัติแจ้งเตือนทั้งหมดที่เคยยิงไปแล้ว เรียงใหม่สุดบนสุด
/// กดอ่านได้ทีละรายการ, ลัดด้วย "อ่านทั้งหมด", ลบทีละอัน/ลบทั้งหมด
/// ===========================================================
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<NotificationItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final items = await NotificationService.instance.getHistory();
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _onTapItem(NotificationItem item) async {
    if (!item.isRead) {
      await NotificationService.instance.markAsRead(item.id);
      await _load();
    }
  }

  Future<void> _onDeleteItem(NotificationItem item) async {
    await NotificationService.instance.deleteOne(item.id);
    await _load();
  }

  Future<void> _onMarkAllRead() async {
    await NotificationService.instance.markAllAsRead();
    await _load();
  }

  Future<void> _onClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบแจ้งเตือนทั้งหมด?'),
        content:
            const Text('เมื่อลบแล้ว คุณจะไม่สามารถย้อนดูประวัติเดิมได้นะคะ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบทั้งหมด', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await NotificationService.instance.clearHistory();
      await _load();
    }
  }

  // ไอคอน/สีของแต่ละประเภทแจ้งเตือน ให้แยกแยะง่ายตาเหมือนแอปทั่วไป
  ({IconData icon, Color color}) _styleForType(String type) {
    switch (type) {
      case 'billing':
        return (
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFF2E7D32)
        );
      case 'meter':
        return (icon: Icons.edit_note_rounded, color: Colors.blueGrey);
      case 'spike':
        return (icon: Icons.trending_up_rounded, color: Colors.red);
      case 'spike':
        return (icon: Icons.trending_up_rounded, color: Colors.red);
      case 'forecast':
        return (icon: Icons.show_chart_rounded, color: Colors.deepOrange);
      case 'summary':
        return (icon: Icons.receipt_long_rounded, color: Colors.orange);
      case 'welcome':
        return (icon: Icons.waving_hand_rounded, color: Colors.purple);
      default:
        return (icon: Icons.notifications_rounded, color: Colors.grey);
    }
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
    if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
    if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
    return DateFormat('d MMM yyyy').format(time);
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = _items.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('การแจ้งเตือน'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0,
        actions: [
          if (hasItems)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'read_all') _onMarkAllRead();
                if (value == 'clear_all') _onClearAll();
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'read_all', child: Text('อ่านทั้งหมด')),
                PopupMenuItem(
                  value: 'clear_all',
                  child: Text('ลบทั้งหมด', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : !hasItems
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: const Color(0xFF2E7D32),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, index) {
                      final item = _items[index];
                      return _buildNotificationTile(item);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('ยังไม่มีการแจ้งเตือน',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(NotificationItem item) {
    final style = _styleForType(item.type);

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _onDeleteItem(item),
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onTapItem(item),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: style.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, color: style.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: item.isRead
                                  ? FontWeight.w500
                                  : FontWeight.bold,
                              color: const Color(0xFF333333),
                            ),
                          ),
                        ),
                        if (!item.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6, top: 4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _timeAgo(item.timestamp),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
