part of 'settings_screen.dart';

// ==================== เลือกวันตัดรอบบิล ====================
// แผ่นเลือกวันตัดรอบบิล (1-31) เปิดจากหน้าตั้งค่า และจากทางลัด
// SettingsQuickAction.billingDay — บันทึกแล้วเรียก [onSaved] ให้หน้าตั้งค่าโหลดใหม่
// ใต้ตารางวันแสดงผลของวันที่เลือก (รอบบิลปัจจุบัน + วันแจ้งเตือน) ก่อนกดบันทึก

void _showBillingDayDialog(
  BuildContext context, {
  required UserModel? user,
  required FirestoreService firestoreService,
  required Future<void> Function() onSaved,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _BillingDaySheet(user: user, firestoreService: firestoreService, onSaved: onSaved),
  );
}

class _BillingDaySheet extends StatefulWidget {
  final UserModel? user;
  final FirestoreService firestoreService;
  final Future<void> Function() onSaved;

  const _BillingDaySheet({required this.user, required this.firestoreService, required this.onSaved});

  @override
  State<_BillingDaySheet> createState() => _BillingDaySheetState();
}

class _BillingDaySheetState extends State<_BillingDaySheet> {
  late int _day = widget.user?.billingDay ?? 30;
  bool _isSaving = false;
  String? _error;

  String _fullDate(DateTime d) => '${d.day} ${thaiMonthsShort[d.month - 1]} ${(d.year + 543) % 100}';

  Future<void> _save() async {
    final user = widget.user;
    final firestoreService = widget.firestoreService;
    final selectedDay = _day;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      // ครั้งแรกสุดที่ user ตั้งวันตัดรอบเอง — เช็คไว้ก่อน updateUser() ด้านล่าง
      // จะเขียนทับค่านี้
      final wasUnconfigured = user?.billingDayConfigured == false;

      // เลขต้นรอบที่ตั้งไว้ตรงกับรอบปัจจุบันอยู่ แต่วันตัดรอบใหม่ทำให้รอบปัจจุบัน
      // เริ่มคนละเดือน — บอกผลก่อนว่าต้องตั้งเลขต้นรอบใหม่ (การ์ดบันทึกมิเตอร์
      // บนหน้าหลักจะล็อก)
      if (user != null && !wasUnconfigured && user.startMeterConfigured && selectedDay != user.billingDay) {
        final matchesNow = EnergyForecaster.matchesCurrentCycle(
          billingMonth: user.startBillingMonth,
          billingYear: user.startBillingYear,
          billingDay: user.billingDay,
        );
        final matchesAfter = EnergyForecaster.matchesCurrentCycle(
          billingMonth: user.startBillingMonth,
          billingYear: user.startBillingYear,
          billingDay: selectedDay,
        );
        if (matchesNow && !matchesAfter) {
          final newStart = EnergyForecaster.getCycleStart(DateTime.now(), selectedDay);
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
          if (!confirmed || !mounted) return;
        }
      }

      final updates = <String, dynamic>{
        'billingDay': selectedDay,
        // ผู้ใช้กดเลือกวันเองจริงแล้วตรงนี้ (ไม่ว่าจะเป็นครั้งแรกหรือมาแก้ทีหลัง)
        // ใช้ปิดตัวเตือน "ยังไม่ได้ตั้งวันตัดรอบบิล" บนหน้าหลัก
        'billingDayConfigured': true,
      };

      // ถ้าก่อนหน้านี้ยังไม่เคยตั้งวันตัดรอบ (billingDay ที่ใช้คำนวณตอนบันทึก
      // มิเตอร์ต้นรอบเป็นค่า default 30 เสมอ) แต่เคยบันทึกมิเตอร์ต้นรอบไปแล้ว
      // เดือนที่คำนวณไว้ตอนนั้นอาจผิดไปจากวันตัดรอบจริงที่เพิ่งเลือก — แก้ให้
      // อัตโนมัติ จำกัดเฉพาะ record แรกสุดจริงๆ (ประวัติมีแค่ 1 รายการ) กันไม่ให้
      // ไปย้อนแก้ประวัติเก่าตอน user มาปรับวันตัดรอบทีหลังจากใช้แอปหลายรอบแล้ว
      if (wasUnconfigured && user!.startMeterConfigured) {
        final history = await firestoreService.getStartMeterHistory(user.uid);
        if (history.length == 1) {
          final record = history.first;
          // ใช้เวลาที่กดบันทึกมิเตอร์จริง (recordedAt) ไม่ใช่เวลาปัจจุบัน กันเดือน
          // เพี้ยนถ้ามาตั้งวันตัดรอบทีหลังจากวันที่กรอกมิเตอร์ไปแล้วหลายวัน
          final corrected = EnergyForecaster.getCycleStart(record.recordedAt, selectedDay);
          if (corrected.month != record.billingMonth || corrected.year != record.billingYear) {
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

            // ย้ายบิลที่ผูกกับเดือนเดิม (กรอกค่าใช้จ่ายไว้พร้อมกันตอนบันทึกมิเตอร์
            // ต้นรอบครั้งแรก) ไปเดือนที่แก้แล้วด้วย ไม่งั้นบิลกับมิเตอร์ต้นรอบจะค้าง
            // อยู่คนละเดือนกัน — ข้ามถ้าเดือนใหม่มีบิลอยู่แล้ว
            final bills = await firestoreService.getBills(user.uid);
            final oldBillMatches =
                bills.where((b) => b.year == record.billingYear && b.month == record.billingMonth);
            final targetTaken = bills.any((b) => b.year == corrected.year && b.month == corrected.month);
            if (oldBillMatches.isNotEmpty && !targetTaken) {
              final oldBill = oldBillMatches.first;
              await firestoreService.saveBill(
                BillModel(
                  id: oldBill.id,
                  uid: oldBill.uid,
                  year: corrected.year,
                  month: corrected.month,
                  electricityUsed: oldBill.electricityUsed,
                  electricityPeakUsed: oldBill.electricityPeakUsed,
                  electricityOffPeakUsed: oldBill.electricityOffPeakUsed,
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

      await firestoreService.updateUser(user!.uid, updates);
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'บันทึกไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _dayCell(int day) {
    final selected = day == _day;
    final isCurrent = widget.user?.billingDayConfigured == true && day == widget.user!.billingDay;
    return Material(
      color: selected ? AppColors.primaryGreen : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(
          color: selected
              ? AppColors.primaryGreen
              : (isCurrent ? AppColors.primaryGreen.withValues(alpha: 0.5) : Colors.grey.shade200),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() {
          _day = day;
          _error = null;
        }),
        child: Center(
          child: Text('$day',
              style: TextStyle(
                  fontSize: AppTypography.s14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.textDark,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ),
    );
  }

  // ผลของวันที่เลือก: รอบบิลปัจจุบัน (ตามกติกาเดียวกับทั้งแอป) และวันแจ้งเตือน
  Widget _preview() {
    final now = DateTime.now();
    final start = EnergyForecaster.getCycleStart(now, _day);
    final end = EnergyForecaster.getCycleEnd(now, _day).subtract(const Duration(days: 1));
    final oldDay = widget.user?.billingDayConfigured == true ? widget.user!.billingDay : null;
    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.v8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: AppSpacing.v8),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade700)),
              ),
              const SizedBox(width: AppSpacing.v8),
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v14, AppSpacing.v10, AppSpacing.v14, AppSpacing.v12),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ตัดรอบทุกวันที่ $_day ของเดือน',
              style: const TextStyle(
                  fontSize: AppTypography.s14, fontWeight: FontWeight.w700, color: AppColors.primaryGreen)),
          if (oldDay != null && oldDay != _day)
            Text('(เดิมวันที่ $oldDay)', style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
          row(Icons.date_range_outlined, 'รอบบิลปัจจุบัน', '${_fullDate(start)} – ${_fullDate(end)}'),
          row(Icons.notifications_none_rounded, 'แจ้งเตือนรอบใหม่', 'วันที่ $_day เวลา 09:00 น.'),
          if (_day > 28)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.v8),
              child: Text('เดือนที่มีไม่ถึง $_day วัน จะตัดรอบวันสุดท้ายของเดือนแทนค่ะ',
                  style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v10, AppSpacing.v16, AppSpacing.v16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetGrabber(),
                const SizedBox(height: AppSpacing.v6),
                Row(
                  children: [
                    const Expanded(
                      child: Text('วันตัดรอบบิล',
                          style: TextStyle(
                              fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    ),
                    IconButton(
                      tooltip: 'วันตัดรอบบิลคืออะไร',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.info_outline, size: 20, color: Colors.grey.shade600),
                      onPressed: () => showInfoDialog(
                        context,
                        title: 'วันตัดรอบบิล คืออะไร?',
                        message: 'วันที่จดเลขมิเตอร์ที่พิมพ์อยู่บนใบแจ้งหนี้ (วันเริ่มรอบบิลใหม่) '
                            'ระบบใช้วันนี้แบ่งรอบบิล คำนวณยอดของแต่ละรอบ และแจ้งเตือน'
                            'ให้คุณบันทึกเลขมิเตอร์ต้นรอบเมื่อได้ใบแจ้งหนี้ใบใหม่\n\n'
                            'ไฟฟ้าและน้ำใช้วันเดียวกัน ถ้าสองใบมาไม่ตรงกัน แนะนำให้เลือก'
                            'ตามใบที่มาทีหลัง',
                      ),
                    ),
                  ],
                ),
                Text('ดูวันที่จดเลขมิเตอร์บนใบแจ้งหนี้ใบล่าสุด แล้วแตะวันนั้นค่ะ',
                    style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600)),
                const SizedBox(height: AppSpacing.v14),
                GridView.count(
                  crossAxisCount: 7,
                  mainAxisSpacing: AppSpacing.v6,
                  crossAxisSpacing: AppSpacing.v6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [for (var d = 1; d <= 31; d++) _dayCell(d)],
                ),
                const SizedBox(height: AppSpacing.v14),
                _preview(),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.v12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: AppSpacing.v6),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.red.shade700)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v16, AppSpacing.v16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: SafeArea(
            top: false,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('บันทึก'),
            ),
          ),
        ),
      ],
    );
  }
}
