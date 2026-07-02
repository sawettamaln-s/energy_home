import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../dashboard/dashboard_screen.dart';
import '../settings/settings_screen.dart';

/// หน้าสรุปหลังทำ setup wizard เสร็จ — โชว์เฉพาะกรณีที่ผู้ใช้ข้ามบางขั้นตอน
/// ไป (วันตัดรอบบิล หรือ บิลตั้งต้น) เพื่อเตือนว่ายังมีอะไรค้างอยู่บ้าง
/// ก่อนเข้าใช้งานจริง ถ้ากรอกครบหมดแล้ว setup_screen.dart จะข้ามหน้านี้ไปเลย
class SetupCompleteScreen extends StatelessWidget {
  final bool billingDayConfigured;
  final bool startMeterConfigured;
  final double startElectricityValue;

  const SetupCompleteScreen({
    super.key,
    required this.billingDayConfigured,
    required this.startMeterConfigured,
    required this.startElectricityValue,
  });

  static const _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: _green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              const Text(
                'พร้อมใช้งานแล้ว!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'ถูกสร้างเรียบร้อยแล้ว ขั้นตอนต่อไปที่แนะนำ',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _checklistItem(
                        icon: Icons.home_rounded,
                        iconBg: const Color(0xFFE8F5E9),
                        iconColor: _green,
                        title: 'วันตัดรอบบิล',
                        subtitle: billingDayConfigured
                            ? 'ตั้งค่าเรียบร้อยแล้ว'
                            : 'ยังไม่ได้ตั้งค่า ไปตั้งได้ที่หน้าตั้งค่า',
                        done: billingDayConfigured,
                      ),
                      const SizedBox(height: 12),
                      _checklistItem(
                        icon: Icons.bolt_rounded,
                        iconBg: const Color(0xFFFFF3E0),
                        iconColor: Colors.orange,
                        title: 'กรอกมิเตอร์ตั้งต้น',
                        subtitle: startMeterConfigured
                            ? '${fmt.format(startElectricityValue)} หน่วย'
                            : 'ยังไม่ได้กรอก ระบบจะยังคำนวณค่าไฟ/น้ำ'
                                'ไม่ได้จนกว่าจะตั้งค่านี้',
                        done: startMeterConfigured,
                      ),
                      const SizedBox(height: 12),
                      _checklistItem(
                        icon: Icons.history_rounded,
                        iconBg: const Color(0xFFE3F2FD),
                        iconColor: Colors.blue,
                        title: 'บิลย้อนหลัง',
                        subtitle: 'สูงสุด 6 เดือน (ไม่บังคับ)',
                        done: false,
                      ),
                      const SizedBox(height: 12),
                      _checklistItem(
                        icon: Icons.list_alt_rounded,
                        iconBg: const Color(0xFFE3F2FD),
                        iconColor: Colors.blue,
                        title: 'Fixed Cost',
                        subtitle: 'ค่าใช้จ่ายประจำบ้าน (ไม่บังคับ)',
                        done: false,
                      ),
                      const SizedBox(height: 12),
                      _checklistItem(
                        icon: Icons.power_rounded,
                        iconBg: const Color(0xFFFCE4EC),
                        iconColor: Colors.pink,
                        title: 'เพิ่มเครื่องใช้ไฟฟ้า',
                        subtitle: 'แนะนำเพื่อวิเคราะห์ที่แม่นยำขึ้น',
                        done: false,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _goToDashboard(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                            const Text('เริ่มใช้งาน', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _goToSettings(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('ตั้งค่าเพิ่มเติมก่อน',
                            style: TextStyle(fontSize: 15)),
                      ),
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

  void _goToDashboard(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (context) =>
              const DashboardScreen(justCompletedSetup: true)),
      (route) => false,
    );
  }

  // ไปหน้า Settings เพื่อแก้ทีละรายการเอง (วันตัดรอบบิล/บิลตั้งต้น) — ตัว
  // Settings เองก็เข้าถึง Dashboard ได้ผ่าน bottom nav bar อยู่แล้ว ไม่ต้อง
  // ทำทางกลับมาที่หน้านี้อีก
  void _goToSettings(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
      (route) => false,
    );
  }

  Widget _checklistItem({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool done,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: done ? _green : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Icon(
            done ? Icons.check_circle : Icons.circle_outlined,
            color: done ? _green : Colors.grey.shade300,
            size: 22,
          ),
        ],
      ),
    );
  }
}