import 'package:flutter/material.dart';

import '../dashboard_styles.dart';

// =====================================================================
// แสดงแทนเนื้อหาหลักเมื่อโหลดข้อมูลไม่สำเร็จ — มีปุ่มลองใหม่ แทนตัวเลข 0
// เงียบๆ ที่ทำให้ผู้ใช้เข้าใจผิดว่าข้อมูลหาย
// =====================================================================
class DashboardLoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const DashboardLoadErrorView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 16),
              const Text(
                'โหลดข้อมูลไม่สำเร็จ',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTypography.s17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTypography.s14,
                    height: 1.5,
                    color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DashboardStyles.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.v32, vertical: AppSpacing.v12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.v12)),
                ),
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
