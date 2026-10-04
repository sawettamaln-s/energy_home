part of 'settings_screen.dart';

// ==================== เลือกวันตัดรอบบิล ====================
// หน้าต่างปฏิทินเลือกวันตัดรอบบิล (1-31) เปิดจากหน้าตั้งค่า และจากทางลัด
// SettingsQuickAction.billingDay — บันทึกแล้วเรียก [onSaved] ให้หน้าตั้งค่าโหลดใหม่

void _billingDayInfo(BuildContext context, String title, String message) {
  showInfoDialog(context, title: title, message: message);
}

// วันที่ "ยอดนิยม" ที่ให้ป้ายกำกับในปฏิทินเลือกวันตัดรอบบิล — เป็นชุดคงที่
// สำหรับความสวยงามของ UI เท่านั้น (แอปยังไม่ได้เก็บสถิติวันที่ผู้ใช้เลือกจริง)
const Set<int> _popularBillingDays = {1, 15, 20, 25, 30};

// ช่องวันที่หนึ่งช่องในปฏิทินเลือกวันตัดรอบบิล (ไม่มีเดือน มีแค่เลข 1-31
// เพราะวันตัดรอบบิลซ้ำทุกเดือนอยู่แล้ว ไม่ต้องให้เลือกเดือน)
Widget _billingDayCell({
  required int day,
  required bool isSelected,
  required bool isPopular,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected ? DashboardStyles.primaryGreen : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v10),
        border: Border.all(
          color: isSelected ? DashboardStyles.primaryGreen : Colors.grey.shade200,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$day',
            style: TextStyle(
              fontSize: AppTypography.s14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
          if (isPopular)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.v1),
              child: Text(
                'ยอดนิยม',
                style: TextStyle(
                  fontSize: AppTypography.s8,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.green.shade700,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

void _showBillingDayDialog(
  BuildContext context, {
  required UserModel? user,
  required FirestoreService firestoreService,
  required Future<void> Function() onSaved,
}) {
  int selectedDay = user?.billingDay ?? 30;
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v20, AppSpacing.v20, AppSpacing.v12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // หัวเรื่อง + ปุ่ม info ห้อยอธิบายว่าวันตัดรอบบิลคืออะไร
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'เลือกวันตัดรอบบิล',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTypography.s17,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.info_outline,
                        color: DashboardStyles.primaryGreen, size: 20),
                    onPressed: () => _billingDayInfo(context, 
                      'วันตัดรอบบิล คืออะไร?',
                      'วันที่จดเลขมิเตอร์ที่พิมพ์อยู่บนใบแจ้งหนี้ (วันเริ่มรอบบิลใหม่) '
                          'ระบบใช้วันนี้แบ่งรอบบิล คำนวณยอดของแต่ละรอบ และแจ้งเตือน'
                          'ให้คุณบันทึกเลขมิเตอร์ต้นรอบเมื่อได้ใบแจ้งหนี้ใบใหม่\n\n'
                          'ไฟฟ้าและน้ำใช้วันเดียวกัน ถ้าสองใบมาไม่ตรงกัน แนะนำให้เลือก'
                          'ตามใบที่มาทีหลัง'
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'แตะที่วันบนใบแจ้งหนี้ล่าสุดของคุณ',
                style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),

              // ปฏิทินเลือกวัน 1-31 แบบกริด 7 คอลัมน์ — mainAxisExtent คงที่
              // เพื่อให้ช่องที่มีป้าย "ยอดนิยม" กับช่องปกติสูงเท่ากัน
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 6,
                  mainAxisExtent: 46,
                ),
                // +1 ช่องแรกเป็นช่องว่าง เพื่อให้เลข 1 เริ่มเยื้องคอลัมน์ที่ 2
                itemCount: 32,
                itemBuilder: (context, i) {
                  if (i == 0) return const SizedBox.shrink();
                  final day = i;
                  return _billingDayCell(
                    day: day,
                    isSelected: day == selectedDay,
                    isPopular: _popularBillingDays.contains(day),
                    onTap: () => setDialogState(() => selectedDay = day),
                  );
                },
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'วันที่เลือก: ทุกวันที่ $selectedDay ของเดือน',
                  style: const TextStyle(
                    fontSize: AppTypography.s12_5,
                    fontWeight: FontWeight.w600,
                    color: DashboardStyles.primaryGreen,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        // ครั้งแรกสุดที่ user ตั้งวันตัดรอบเอง — เช็คไว้ก่อน
                        // updateUser() ด้านล่างจะเขียนทับค่านี้
                        final wasUnconfigured =
                            user?.billingDayConfigured == false;

                        // เลขต้นรอบที่ตั้งไว้ตรงกับรอบปัจจุบันอยู่ แต่วันตัดรอบ
                        // ใหม่ทำให้รอบปัจจุบันเริ่มคนละเดือน — บอกผลก่อนว่าต้อง
                        // ตั้งเลขต้นรอบใหม่ (การ์ดบันทึกมิเตอร์บนหน้าหลักจะล็อก)
                        if (user != null &&
                            !wasUnconfigured &&
                            user.startMeterConfigured &&
                            selectedDay != user.billingDay) {
                          final matchesNow =
                              EnergyForecaster.matchesCurrentCycle(
                            billingMonth: user.startBillingMonth,
                            billingYear: user.startBillingYear,
                            billingDay: user.billingDay,
                          );
                          final matchesAfter =
                              EnergyForecaster.matchesCurrentCycle(
                            billingMonth: user.startBillingMonth,
                            billingYear: user.startBillingYear,
                            billingDay: selectedDay,
                          );
                          if (matchesNow && !matchesAfter) {
                            final newStart = EnergyForecaster.getCycleStart(
                                DateTime.now(), selectedDay);
                            final confirmed = await showConfirmDialog(
                              context,
                              title: 'เปลี่ยนวันตัดรอบบิล?',
                              content: 'เมื่อเปลี่ยนเป็นวันที่ $selectedDay '
                                  'รอบบิลปัจจุบันจะเริ่ม ${newStart.day} '
                                  '${thaiMonths[newStart.month - 1]} '
                                  '${newStart.year + 543} ซึ่งไม่ตรงกับเลข'
                                  'มิเตอร์ต้นรอบที่ตั้งไว้ ต้องตั้งเลขมิเตอร์'
                                  'ต้นรอบใหม่ก่อนบันทึกมิเตอร์ต่อค่ะ',
                              confirmLabel: 'เปลี่ยน',
                              confirmColor: DashboardStyles.primaryGreen,
                            );
                            if (!confirmed || !context.mounted) return;
                          }
                        }

                        final updates = <String, dynamic>{
                          'billingDay': selectedDay,
                          // ผู้ใช้กดเลือกวันเองจริงแล้วตรงนี้ (ไม่ว่าจะ
                          // เป็นครั้งแรกหรือมาแก้ทีหลัง) ใช้ปิดตัวเตือน
                          // "ยังไม่ได้ตั้งวันตัดรอบบิล" บนหน้าหลัก
                          'billingDayConfigured': true,
                        };

                        // ถ้าก่อนหน้านี้ยังไม่เคยตั้งวันตัดรอบ (billingDay ที่ใช้
                        // คำนวณตอนบันทึกมิเตอร์ต้นรอบเป็นค่า default 30 เสมอ) แต่
                        // เคยบันทึกมิเตอร์ต้นรอบไปแล้ว เดือนที่คำนวณไว้ตอนนั้นอาจ
                        // ผิดไปจากวันตัดรอบจริงที่เพิ่งเลือก — แก้ให้อัตโนมัติ
                        // แทนที่จะให้ user ต้องกลับมากรอกมิเตอร์ต้นรอบใหม่เอง
                        // จำกัดเฉพาะ record แรกสุดจริงๆ (ประวัติมีแค่ 1 รายการ)
                        // เท่านั้น กันไม่ให้ไปย้อนแก้ประวัติเก่าตอน user มาปรับวัน
                        // ตัดรอบทีหลังจากใช้แอปผ่านไปหลายรอบบิลแล้ว (เคสนั้นคือ
                        // เปลี่ยนวันตัดรอบจริงๆ ไม่ใช่แก้ค่าที่ผิดจาก default)
                        if (wasUnconfigured && user!.startMeterConfigured) {
                          final history = await firestoreService
                              .getStartMeterHistory(user.uid);
                          if (history.length == 1) {
                            final record = history.first;
                            // ใช้เวลาที่กดบันทึกมิเตอร์จริง (recordedAt) ไม่ใช่
                            // เวลาปัจจุบัน กันเดือนเพี้ยนซ้ำถ้ามาตั้งวันตัดรอบ
                            // ทีหลังจากวันที่กรอกมิเตอร์ไปแล้วหลายวัน
                            final corrected = EnergyForecaster.getCycleStart(
                                record.recordedAt, selectedDay);
                            if (corrected.month != record.billingMonth ||
                                corrected.year != record.billingYear) {
                              updates['startBillingMonth'] = corrected.month;
                              updates['startBillingYear'] = corrected.year;

                              await firestoreService.saveStartMeterRecord(
                                StartMeterRecordModel(
                                  id: record.id,
                                  uid: record.uid,
                                  electricityValue: record.electricityValue,
                                  waterValue: record.waterValue,
                                  peakValue: record.peakValue,
                                  offPeakValue: record.offPeakValue,
                                  billingMonth: corrected.month,
                                  billingYear: corrected.year,
                                  recordedAt: record.recordedAt,
                                ),
                              );

                              // ย้ายบิลที่ผูกกับเดือนเดิม (ถ้ามี กรอกค่าใช้จ่าย
                              // ไว้พร้อมกันตอนบันทึกมิเตอร์ต้นรอบครั้งแรก) ไป
                              // เดือนที่แก้แล้วด้วย ไม่งั้นบิลกับมิเตอร์ต้นรอบจะ
                              // ค้างอยู่คนละเดือนกัน — ข้ามถ้าเดือนใหม่ดันมีบิล
                              // อยู่แล้ว (ชนกัน แทบเป็นไปไม่ได้ตอน history มีแค่
                              // 1 รายการ แต่กันไว้เผื่อ)
                              final bills = await firestoreService
                                  .getBills(user.uid);
                              final oldBillMatches = bills.where((b) =>
                                  b.year == record.billingYear &&
                                  b.month == record.billingMonth);
                              final targetTaken = bills.any((b) =>
                                  b.year == corrected.year &&
                                  b.month == corrected.month);
                              if (oldBillMatches.isNotEmpty &&
                                  !targetTaken) {
                                final oldBill = oldBillMatches.first;
                                await firestoreService.saveBill(
                                  BillModel(
                                    id: oldBill.id,
                                    uid: oldBill.uid,
                                    year: corrected.year,
                                    month: corrected.month,
                                    electricityUsed: oldBill.electricityUsed,
                                    electricityPeakUsed:
                                        oldBill.electricityPeakUsed,
                                    electricityOffPeakUsed:
                                        oldBill.electricityOffPeakUsed,
                                    waterUsed: oldBill.waterUsed,
                                    electricityCost: oldBill.electricityCost,
                                    waterCost: oldBill.waterCost,
                                    fixedCost: oldBill.fixedCost,
                                    totalCost: oldBill.totalCost,
                                    source: oldBill.source,
                                  ),
                                );
                              }
                            }
                          }
                        }

                        await firestoreService.updateUser(
                            user!.uid, updates);
                        await onSaved();
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DashboardStyles.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.v12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.v10),
                        ),
                      ),
                      child: const Text('บันทึก'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
