import 'package:flutter/material.dart';

import '../screens/dashboard/dashboard_styles.dart';
import 'info_dialog.dart';

/// ===========================================================
/// StartMeterValidation
/// ===========================================================
/// กติกาการกรอกเลขมิเตอร์ต้นรอบ + ค่าใช้จ่าย: แยกเป็น "คู่ไฟ" กับ "คู่น้ำ"
/// แต่ละคู่ต้องกรอกครบทั้งเลขมิเตอร์และค่าใช้จ่าย หรือเว้นว่างทั้งคู่เท่านั้น
/// (ห้ามกรอกครึ่งเดียว) และต้องมีอย่างน้อย 1 คู่ที่ครบถึงจะบันทึกได้ — เว้น
/// แต่ติ๊ก "ยังไม่มีบิลตอนนี้" ของฝั่งนั้นๆ ซึ่งจะยกเว้นข้อบังคับเรื่อง
/// ค่าใช้จ่ายไป (เหลือแค่ต้องมีเลขมิเตอร์) — แยก noBillYet เป็นรายยูทิลิตี้
/// แล้ว (eNoBillYet/wNoBillYet) เพราะมีบิลแค่ฝั่งเดียวได้ตามปกติ
///
/// เพิ่ม isFirstEntry/eUsed/wUsed: ถ้าเป็นการตั้งค่าครั้งแรกสุดของยูทิลิตี้
/// นั้นๆ (ไม่เคยมี record ก่อนหน้าที่มีค่า > 0 มาก่อนเลย) จะคำนวณ "หน่วยที่
/// ใช้ไปแล้ว" แบบ delta (รอบนี้ - รอบก่อนหน้า) ไม่ได้จริงๆ เพราะไม่มีรอบก่อน
/// หน้าให้เทียบ ต้องให้ผู้ใช้กรอกเองแทน ช่องนี้จึงกลายเป็นช่องบังคับเพิ่มเข้า
/// มาเฉพาะตอน isFirstEntry เท่านั้น (ครั้งต่อๆ ไปไม่ต้องกรอกอีก เพราะคำนวณ
/// จาก record ก่อนหน้าได้แล้ว)
///
/// รวม logic ไว้ที่เดียวเป็น static function ให้ทั้ง widget นี้เอง (โชว์ error
/// รายการ์ด) และหน้าที่เรียกใช้ (เช็คก่อนกด "บันทึก") เรียกใช้ตัวเดียวกัน
/// กันไม่ให้กติกาดริฟท์ไปคนละทางระหว่าง UI กับ validation ตอน save จริง
class StartMeterValidation {
  static bool electricityMeterOk({
    required bool isTou,
    required double eVal,
    required double peakVal,
    required double offPeakVal,
  }) =>
      isTou ? (peakVal > 0 && offPeakVal > 0) : eVal > 0;

  static bool electricityMeterTouched({
    required bool isTou,
    required double eVal,
    required double peakVal,
    required double offPeakVal,
  }) =>
      isTou ? (peakVal > 0 || offPeakVal > 0) : eVal > 0;

  static bool electricityFilled({
    required bool isTou,
    required double eVal,
    required double peakVal,
    required double offPeakVal,
    required double eCost,
    double eUsed = 0,
  }) =>
      electricityMeterTouched(
          isTou: isTou, eVal: eVal, peakVal: peakVal, offPeakVal: offPeakVal) ||
      eCost > 0 ||
      eUsed > 0;

  static bool electricityComplete({
    required bool isTou,
    required double eVal,
    required double peakVal,
    required double offPeakVal,
    required double eCost,
    required bool eNoBillYet,
    bool isFirstEntry = false,
    double eUsed = 0,
  }) {
    if (!electricityMeterOk(
        isTou: isTou, eVal: eVal, peakVal: peakVal, offPeakVal: offPeakVal)) {
      return false;
    }
    if (!(eNoBillYet || eCost > 0)) return false;
    if (isFirstEntry && eUsed <= 0) return false;
    return true;
  }

  static bool electricityPartial({
    required bool isTou,
    required double eVal,
    required double peakVal,
    required double offPeakVal,
    required double eCost,
    required bool eNoBillYet,
    bool isFirstEntry = false,
    double eUsed = 0,
  }) =>
      electricityFilled(
          isTou: isTou,
          eVal: eVal,
          peakVal: peakVal,
          offPeakVal: offPeakVal,
          eCost: eCost,
          eUsed: eUsed) &&
      !electricityComplete(
          isTou: isTou,
          eVal: eVal,
          peakVal: peakVal,
          offPeakVal: offPeakVal,
          eCost: eCost,
          eNoBillYet: eNoBillYet,
          isFirstEntry: isFirstEntry,
          eUsed: eUsed);

  static bool waterFilled({
    required double wVal,
    required double wCost,
    double wUsed = 0,
  }) =>
      wVal > 0 || wCost > 0 || wUsed > 0;

  static bool waterComplete({
    required double wVal,
    required double wCost,
    required bool wNoBillYet,
    bool isFirstEntry = false,
    double wUsed = 0,
  }) {
    if (wVal <= 0) return false;
    if (!(wNoBillYet || wCost > 0)) return false;
    if (isFirstEntry && wUsed <= 0) return false;
    return true;
  }

  static bool waterPartial({
    required double wVal,
    required double wCost,
    required bool wNoBillYet,
    bool isFirstEntry = false,
    double wUsed = 0,
  }) =>
      waterFilled(wVal: wVal, wCost: wCost, wUsed: wUsed) &&
      !waterComplete(
          wVal: wVal,
          wCost: wCost,
          wNoBillYet: wNoBillYet,
          isFirstEntry: isFirstEntry,
          wUsed: wUsed);

  /// เช็ครวมว่ากด "บันทึก" ได้ไหม — ไม่มีคู่ไหนกรอกครึ่งเดียวค้างอยู่ และ
  /// มีอย่างน้อย 1 คู่ที่ครบ
  static bool canSave({
    required bool isTou,
    required double eVal,
    required double peakVal,
    required double offPeakVal,
    required double eCost,
    required double wVal,
    required double wCost,
    required bool eNoBillYet,
    required bool wNoBillYet,
    bool eIsFirstEntry = false,
    double eUsed = 0,
    bool wIsFirstEntry = false,
    double wUsed = 0,
  }) {
    final eComplete = electricityComplete(
        isTou: isTou,
        eVal: eVal,
        peakVal: peakVal,
        offPeakVal: offPeakVal,
        eCost: eCost,
        eNoBillYet: eNoBillYet,
        isFirstEntry: eIsFirstEntry,
        eUsed: eUsed);
    final wComplete = waterComplete(
        wVal: wVal,
        wCost: wCost,
        wNoBillYet: wNoBillYet,
        isFirstEntry: wIsFirstEntry,
        wUsed: wUsed);
    final ePartial = electricityPartial(
        isTou: isTou,
        eVal: eVal,
        peakVal: peakVal,
        offPeakVal: offPeakVal,
        eCost: eCost,
        eNoBillYet: eNoBillYet,
        isFirstEntry: eIsFirstEntry,
        eUsed: eUsed);
    final wPartial = waterPartial(
        wVal: wVal,
        wCost: wCost,
        wNoBillYet: wNoBillYet,
        isFirstEntry: wIsFirstEntry,
        wUsed: wUsed);
    return (eComplete || wComplete) && !ePartial && !wPartial;
  }
}

/// ===========================================================
/// StartMeterPairedFields
/// ===========================================================
/// ชุดฟิลด์ "เลขมิเตอร์สะสมต้นรอบ + ค่าใช้จ่ายบิลล่าสุด" ที่ใช้ร่วมกันทั้ง 2
/// จุดในแอป: หน้าตั้งค่า > บันทึกมิเตอร์ต้นรอบ (settings_screen.dart) และ
/// ขั้นตอนตั้งค่าเริ่มต้นตอนสมัคร (setup_screen.dart)
///
/// ปรับใหม่: เดิมโชว์การ์ดไฟฟ้า+น้ำพร้อมกันทั้งคู่ ทำให้หน้ายาวเกินไป
/// โดยเฉพาะตอนสมัครที่มีทั้ง 2 ยูทิลิตี้ + toggle "ยังไม่มีบิล" รวมกันเป็น
/// ก้อนเดียว ตอนนี้เปลี่ยนเป็นแท็บเลือก "ไฟฟ้า / น้ำ" แล้วโชว์แค่การ์ดของ
/// ฝั่งที่เลือกอยู่ — แท็บมีเครื่องหมายถูกกำกับเมื่อฝั่งนั้นกรอกครบแล้ว
/// (ไม่ต้องสลับไปมาเพื่อเช็คว่ากรอกครบหรือยัง) ส่วน toggle "ยังไม่มีบิล
/// ตอนนี้" ย้ายเข้าไปอยู่ในการ์ดของแต่ละฝั่งแยกกัน (เดิมเป็นตัวเดียวใช้ร่วม
/// ทั้งไฟและน้ำ ทำให้ติ๊กแล้วกระทบทั้งคู่พร้อมกันทั้งที่บางทีมีบิลแค่ฝั่ง
/// เดียว) — state ของแท็บที่เลือกอยู่เก็บไว้ในตัว widget เอง เพราะเป็นแค่
/// UI state ล้วนๆ ไม่กระทบข้อมูลจริงที่หน้าเรียกใช้ต้องรู้
class StartMeterPairedFields extends StatefulWidget {
  final bool isTou;
  final TextEditingController electricityCtrl;
  final TextEditingController peakCtrl;
  final TextEditingController offPeakCtrl;
  final TextEditingController eCostCtrl;
  final TextEditingController waterCtrl;
  final TextEditingController wCostCtrl;

  // ช่องที่ 3 "หน่วยที่ใช้ไปแล้ว" — โชว์เฉพาะตอน isFirstEntry ของยูทิลิตี้
  // นั้นๆ เป็น true (ไม่เคยมี record ก่อนหน้าที่มีค่า > 0 มาก่อนเลย จึง
  // คำนวณ delta ไม่ได้จริงๆ) เช็คเป็นรายยูทิลิตี้แยกกัน ไม่ใช่เช็ครวมทั้ง
  // บัญชี เพราะตั้งแยกยูทิลิตี้ได้อิสระแล้ว
  final TextEditingController eUsedCtrl;
  final TextEditingController wUsedCtrl;
  // เฉพาะ TOU: แยกช่อง "หน่วยที่ใช้ไปแล้ว" เป็น On-Peak/Off-Peak คู่กัน
  // เหมือนช่องเลขมิเตอร์ด้านบน แล้วรวมให้อัตโนมัติแทน eUsedCtrl ตัวเดียว
  // (ไม่ required เพราะตารางน้ำ/มิเตอร์ปกติไม่ใช้)
  final TextEditingController? eUsedPeakCtrl;
  final TextEditingController? eUsedOffPeakCtrl;
  final bool eIsFirstEntry;
  final bool wIsFirstEntry;

  // แยกเป็นรายยูทิลิตี้แล้ว (เดิมเป็น noBillYet ตัวเดียวใช้ร่วมกันทั้งคู่)
  final bool eNoBillYet;
  final ValueChanged<bool> onENoBillYetChanged;
  final bool wNoBillYet;
  final ValueChanged<bool> onWNoBillYetChanged;

  /// หัวข้อ/คำอธิบายรวมด้านบนสุด — ปรับได้ตามบริบท (หน้าเซตอัพ vs หน้าตั้งค่า)
  final String title;
  final String subtitle;

  const StartMeterPairedFields({
    super.key,
    required this.isTou,
    required this.electricityCtrl,
    required this.peakCtrl,
    required this.offPeakCtrl,
    required this.eCostCtrl,
    required this.waterCtrl,
    required this.wCostCtrl,
    required this.eUsedCtrl,
    required this.wUsedCtrl,
    this.eUsedPeakCtrl,
    this.eUsedOffPeakCtrl,
    this.eIsFirstEntry = false,
    this.wIsFirstEntry = false,
    required this.eNoBillYet,
    required this.onENoBillYetChanged,
    required this.wNoBillYet,
    required this.onWNoBillYetChanged,
    required this.title,
    required this.subtitle,
  });

  @override
  State<StartMeterPairedFields> createState() =>
      _StartMeterPairedFieldsState();
}

class _StartMeterPairedFieldsState extends State<StartMeterPairedFields> {
  // 0 = ไฟฟ้า, 1 = น้ำ
  int _selectedTab = 0;

  double _num(TextEditingController c) => double.tryParse(c.text) ?? 0;

  void _showWhatIsThisPopup(BuildContext context) {
    showInfoDialog(
      context,
      title: 'กรอกตรงไหนของบิล?',
      contentBuilder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '"เลขมิเตอร์สะสม" เปิดใบแจ้งหนี้ แล้วมองหาช่อง "เลขอ่านครั้งหลัง" '
            'หรือ "Last Meter Reading" — คือตัวเลขที่มิเตอร์อ่านได้ล่าสุด '
            'ตอนเจ้าหน้าที่มาจดในรอบบิลนั้น (ไม่ใช่ "เลขอ่านครั้งก่อน" '
            'ที่อยู่คู่กัน เพราะเป็นเลขของรอบก่อนหน้า)',
            style: TextStyle(fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: 10),
          const Text(
            '"ค่าใช้จ่าย" คือยอดที่ต้องจ่ายของบิลใบเดียวกัน — กรอกเป็นคู่กับ'
            'เลขมิเตอร์ด้านบนเสมอ ถ้ายังไม่มีบิลของฝั่งไหน ให้เว้นว่างทั้ง'
            'เลขมิเตอร์และค่าใช้จ่ายของฝั่งนั้นไปเลย',
            style: TextStyle(fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.straighten, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'เลขมิเตอร์สะสมเป็นเลขบนหน้าปัดตั้งแต่วันติดตั้ง ไม่ใช่ '
                    '"หน่วยที่ใช้เดือนนี้" — ถ้าเพิ่งเปลี่ยนมิเตอร์ใหม่หรือ'
                    'เพิ่งขอมิเตอร์ครั้งแรก เลขนี้อาจเริ่มจากตัวเลขน้อยๆ '
                    'ได้ตามปกติ ไม่ต้องกังวล',
                    style: TextStyle(
                        fontSize: 12.5, height: 1.5, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required String suffixText,
    required IconData icon,
    required Color iconColor,
  }) {
    return InputDecoration(
      hintText: hint,
      suffixText: suffixText,
      prefixIcon: Icon(icon, color: iconColor, size: 20),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }

  // ช่องที่ 3 "หน่วยที่ใช้ไปแล้ว" — ต่างจาก _field ปกติตรงมีคำอธิบายกำกับ
  // ไว้ด้วยเสมอ เพราะเป็นช่องที่โผล่มาแบบไม่คาดคิด ต้องอธิบายให้ชัดว่าทำไม
  // ต้องกรอกเพิ่ม ไม่งั้นจะดูเหมือนระบบขอข้อมูลซ้ำซ้อนกับ "เลขมิเตอร์สะสม"
  Widget _usedField({
    required TextEditingController controller,
    required String hint,
    required String suffixText,
    required Color iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          controller: controller,
          label: 'หน่วยที่ใช้ไปแล้วในรอบนี้ (ครั้งแรกเท่านั้น)',
          hint: hint,
          suffixText: suffixText,
          icon: Icons.bar_chart,
          iconColor: iconColor,
        ),
        const SizedBox(height: 4),
        Text(
          'ตั้งค่าครั้งแรก ระบบยังไม่มีเลขของรอบก่อนหน้าให้เทียบหาหน่วยที่ใช้'
          'ให้อัตโนมัติ — กรอกจากใบแจ้งหนี้ใบเดียวกับเลขมิเตอร์สะสมด้านบน'
          '(ช่อง "หน่วยที่ใช้" หรือ "จำนวนหน่วย")',
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // เวอร์ชัน TOU ของ _usedField — แยก On-Peak/Off-Peak เป็นคนละช่อง (สอดคล้อง
  // กับเลขมิเตอร์ด้านบนที่แยกอยู่แล้ว) แล้วโชว์ผลรวมให้ดูสดๆ ไม่ต้องให้
  // ผู้ใช้บวกเลขเอง — ผลรวมนี้คือค่าที่ถูกใช้เป็น eUsed จริงตอน validate/save
  // (ดู eUsed ใน build() ด้านล่าง)
  Widget _usedFieldTou({
    required TextEditingController peakCtrl,
    required TextEditingController offPeakCtrl,
    required Color iconColor,
  }) {
    final sum = _num(peakCtrl) + _num(offPeakCtrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('หน่วยที่ใช้ไปแล้วในรอบนี้ (ครั้งแรกเท่านั้น)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 340;
            final peakField = _field(
              controller: peakCtrl,
              label: 'On-Peak',
              hint: 'เช่น 1,655',
              suffixText: 'หน่วย',
              icon: Icons.bolt,
              iconColor: iconColor,
            );
            final offPeakField = _field(
              controller: offPeakCtrl,
              label: 'Off-Peak',
              hint: 'เช่น 1,000',
              suffixText: 'หน่วย',
              icon: Icons.bolt_outlined,
              iconColor: iconColor,
            );
            if (narrow) {
              return Column(children: [
                peakField,
                const SizedBox(height: 10),
                offPeakField,
              ]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: peakField),
                const SizedBox(width: 10),
                Expanded(child: offPeakField),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          'On-Peak + Off-Peak = รวม ${sum.toStringAsFixed(0)} หน่วย '
          '(คำนวณให้อัตโนมัติ)',
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: iconColor),
        ),
        const SizedBox(height: 4),
        Text(
          'ตั้งค่าครั้งแรก ระบบยังไม่มีเลขของรอบก่อนหน้าให้เทียบหาหน่วยที่ใช้'
          'ให้อัตโนมัติ — กรอกจากใบแจ้งหนี้ใบเดียวกับเลขมิเตอร์สะสมด้านบน '
          '(ช่อง "หน่วยที่ใช้" แยก On-Peak/Off-Peak)',
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String suffixText,
    required IconData icon,
    required Color iconColor,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _decoration(
              hint: hint, suffixText: suffixText, icon: icon, iconColor: iconColor),
        ),
      ],
    );
  }

  // แท็บเลือกไฟฟ้า/น้ำ — ✓ สีเขียวโผล่ข้างชื่อแท็บเมื่อฝั่งนั้นกรอกครบแล้ว
  // (isPartial ก็จะไม่ขึ้น ✓ ด้วย เพราะยังไม่ถือว่า "ครบ" ตามนิยาม complete)
  Widget _buildTabs({required bool eComplete, required bool wComplete}) {
    return Row(
      children: [
        Expanded(
          child: _tabChip(
            label: 'ไฟฟ้า',
            icon: Icons.bolt,
            color: DashboardStyles.electricityBorder,
            selected: _selectedTab == 0,
            complete: eComplete,
            onTap: () => setState(() => _selectedTab = 0),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _tabChip(
            label: 'น้ำ',
            icon: Icons.water_drop,
            color: DashboardStyles.waterBorder,
            selected: _selectedTab == 1,
            complete: wComplete,
            onTap: () => setState(() => _selectedTab = 1),
          ),
        ),
      ],
    );
  }

  Widget _tabChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required bool complete,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? color : Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? color : Colors.grey.shade700,
              ),
            ),
            if (complete) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_circle, size: 14, color: Colors.green),
            ],
          ],
        ),
      ),
    );
  }

  Widget _utilityCard({
    required BuildContext context,
    required String label,
    required Color borderColor,
    required Color accentColor,
    required Widget meterFields,
    required TextEditingController costCtrl,
    required String costHint,
    required bool isPartial,
    required bool noBillYet,
    required ValueChanged<bool> onNoBillYetChanged,
    Widget? usedField,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: DashboardStyles.accentCard(borderColor, radius: 14).copyWith(
        color: borderColor.withValues(alpha: 0.045),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    label == 'ไฟฟ้า' ? Icons.bolt : Icons.water_drop,
                    size: 15,
                    color: accentColor),
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              if (isPartial)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('กรอกไม่ครบ',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade700)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          meterFields,
          if (usedField != null) ...[
            const SizedBox(height: 10),
            usedField,
          ],
          const SizedBox(height: 10),
          _field(
            controller: costCtrl,
            label: 'ค่าใช้จ่าย',
            hint: costHint,
            suffixText: 'บาท',
            icon: Icons.receipt_long,
            iconColor: accentColor,
            enabled: !noBillYet,
          ),
          const SizedBox(height: 10),
          // toggle "ยังไม่มีบิลตอนนี้" — ย้ายมาไว้ในการ์ดของฝั่งนี้โดยเฉพาะ
          // แล้ว (เดิมเป็นตัวเดียวรวมทั้งไฟและน้ำ) กดแล้วกระทบแค่ฝั่งนี้
          // ใช้ checkbox วงกลมแทนสวิตช์วงรี ให้เข้าชุดกับการ์ด "ข้าม
          // ขั้นตอนนี้" ในหน้าเซตอัพ — ทำทั้งแถวกดได้ ไม่ต้องเล็งตัวสวิตช์
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onNoBillYetChanged(!noBillYet),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ยังไม่มีบิล$labelตอนนี้ (มีแต่เลขมิเตอร์ที่อ่านจากหน้าปัดเอง)',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  noBillYet ? Icons.check_circle : Icons.circle_outlined,
                  color: noBillYet ? const Color(0xFF2E7D32) : Colors.grey.shade400,
                  size: 22,
                ),
              ],
            ),
          ),
          if (isPartial) ...[
            const SizedBox(height: 8),
            Text(
              'กรอกให้ครบทุกช่องของ$label หรือเว้นว่างทั้งหมดถ้ายัง'
              'ไม่มีบิล$labelในมือ',
              style: TextStyle(fontSize: 11.5, color: Colors.red.shade600),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eVal = _num(widget.electricityCtrl);
    final peakVal = _num(widget.peakCtrl);
    final offPeakVal = _num(widget.offPeakCtrl);
    final eCost = _num(widget.eCostCtrl);
    // TOU: eUsed มาจากผลรวม On-Peak/Off-Peak ที่กรอกแยก (auto-sum) แทนช่อง
    // เดียวแบบเดิม — ไม่งั้น validate/save จะยังอิง eUsedCtrl ตัวเดียวซึ่ง
    // ไม่มีช่องให้กรอกแล้วในโหมด TOU (ดู usedField ด้านล่าง)
    final eUsedPeakInput =
        widget.eUsedPeakCtrl == null ? 0.0 : _num(widget.eUsedPeakCtrl!);
    final eUsedOffPeakInput = widget.eUsedOffPeakCtrl == null
        ? 0.0
        : _num(widget.eUsedOffPeakCtrl!);
    final eUsed = widget.isTou
        ? eUsedPeakInput + eUsedOffPeakInput
        : _num(widget.eUsedCtrl);
    final wVal = _num(widget.waterCtrl);
    final wCost = _num(widget.wCostCtrl);
    final wUsed = _num(widget.wUsedCtrl);

    final eComplete = StartMeterValidation.electricityComplete(
        isTou: widget.isTou,
        eVal: eVal,
        peakVal: peakVal,
        offPeakVal: offPeakVal,
        eCost: eCost,
        eNoBillYet: widget.eNoBillYet,
        isFirstEntry: widget.eIsFirstEntry,
        eUsed: eUsed);
    final wComplete = StartMeterValidation.waterComplete(
        wVal: wVal,
        wCost: wCost,
        wNoBillYet: widget.wNoBillYet,
        isFirstEntry: widget.wIsFirstEntry,
        wUsed: wUsed);

    final ePartial = StartMeterValidation.electricityPartial(
        isTou: widget.isTou,
        eVal: eVal,
        peakVal: peakVal,
        offPeakVal: offPeakVal,
        eCost: eCost,
        eNoBillYet: widget.eNoBillYet,
        isFirstEntry: widget.eIsFirstEntry,
        eUsed: eUsed);
    final wPartial = StartMeterValidation.waterPartial(
        wVal: wVal,
        wCost: wCost,
        wNoBillYet: widget.wNoBillYet,
        isFirstEntry: widget.wIsFirstEntry,
        wUsed: wUsed);

    final electricityMeterFields = widget.isTou
        ? LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 340;
              final peakField = _field(
                controller: widget.peakCtrl,
                label: 'เลขมิเตอร์ On-Peak',
                hint: 'เช่น 8,500',
                suffixText: 'หน่วย',
                icon: Icons.bolt,
                iconColor: DashboardStyles.electricityBorder,
              );
              final offPeakField = _field(
                controller: widget.offPeakCtrl,
                label: 'เลขมิเตอร์ Off-Peak',
                hint: 'เช่น 5,500',
                suffixText: 'หน่วย',
                icon: Icons.bolt_outlined,
                iconColor: DashboardStyles.electricityBorder,
              );
              if (narrow) {
                return Column(children: [
                  peakField,
                  const SizedBox(height: 10),
                  offPeakField,
                ]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: peakField),
                  const SizedBox(width: 10),
                  Expanded(child: offPeakField),
                ],
              );
            },
          )
        : _field(
            controller: widget.electricityCtrl,
            label: 'เลขมิเตอร์สะสม',
            hint: 'เช่น 14,009',
            suffixText: 'หน่วย',
            icon: Icons.speed,
            iconColor: DashboardStyles.electricityBorder,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
              onPressed: () => _showWhatIsThisPopup(context),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(widget.subtitle,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        _buildTabs(eComplete: eComplete, wComplete: wComplete),
        const SizedBox(height: 12),
        if (_selectedTab == 0)
          _utilityCard(
            context: context,
            label: 'ไฟฟ้า',
            borderColor: DashboardStyles.electricityBorder,
            accentColor: DashboardStyles.electricityBorder,
            meterFields: electricityMeterFields,
            costCtrl: widget.eCostCtrl,
            costHint: 'เช่น 850',
            isPartial: ePartial,
            noBillYet: widget.eNoBillYet,
            onNoBillYetChanged: widget.onENoBillYetChanged,
            usedField: widget.eIsFirstEntry
                ? (widget.isTou && widget.eUsedPeakCtrl != null &&
                        widget.eUsedOffPeakCtrl != null
                    ? _usedFieldTou(
                        peakCtrl: widget.eUsedPeakCtrl!,
                        offPeakCtrl: widget.eUsedOffPeakCtrl!,
                        iconColor: DashboardStyles.electricityBorder,
                      )
                    : _usedField(
                        controller: widget.eUsedCtrl,
                        hint: 'เช่น 2,655',
                        suffixText: 'หน่วย',
                        iconColor: DashboardStyles.electricityBorder,
                      ))
                : null,
          )
        else
          _utilityCard(
            context: context,
            label: 'น้ำ',
            borderColor: DashboardStyles.waterBorder,
            accentColor: DashboardStyles.waterBorder,
            meterFields: _field(
              controller: widget.waterCtrl,
              label: 'เลขมิเตอร์สะสม',
              hint: 'เช่น 148',
              suffixText: 'ลบ.ม.',
              icon: Icons.speed,
              iconColor: DashboardStyles.waterBorder,
            ),
            costCtrl: widget.wCostCtrl,
            costHint: 'เช่น 120',
            isPartial: wPartial,
            noBillYet: widget.wNoBillYet,
            onNoBillYetChanged: widget.onWNoBillYetChanged,
            usedField: widget.wIsFirstEntry
                ? _usedField(
                    controller: widget.wUsedCtrl,
                    hint: 'เช่น 108',
                    suffixText: 'ลบ.ม.',
                    iconColor: DashboardStyles.waterBorder,
                  )
                : null,
          ),
      ],
    );
  }
}