part of 'settings_screen.dart';

// ==================== อธิบายอัตราค่าไฟฟ้า / น้ำ ====================
// จุดประสงค์: ผู้ใช้เห็นแค่ตัวเลขบิลผลลัพธ์ แต่ไม่รู้ว่าทำไมได้ตัวเลขนี้
// หน้านี้เป็น static content ล้วนๆ (ยกเว้นค่า Ft ที่ดึงสดจาก Firestore)
// ไม่มีการบันทึกหรือแก้ไขข้อมูลใดๆ แค่โชว์ตารางอัตรา + คำอธิบายตามเกณฑ์
// (พื้นที่ + ประเภทมิเตอร์) ที่ผู้ใช้ตั้งไว้จริงในโปรไฟล์
class _RateExplanationScreen extends StatefulWidget {
  final String area; // 'bangkok' (MEA/MWA) หรือ 'province' (PEA/PWA)
  final String meterType; // 'normal' หรือ 'tou'

  const _RateExplanationScreen({
    required this.area,
    required this.meterType,
  });

  @override
  State<_RateExplanationScreen> createState() =>
      _RateExplanationScreenState();
}

class _RateExplanationScreenState extends State<_RateExplanationScreen>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF2E7D32);
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('อัตราค่าไฟฟ้า / น้ำ'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.bolt), text: 'ไฟฟ้า'),
            Tab(icon: Icon(Icons.water_drop), text: 'น้ำ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ElectricityRateTab(area: widget.area, meterType: widget.meterType),
          _WaterRateTab(area: widget.area),
        ],
      ),
    );
  }
}

// ปุ่ม (i) เปิด popup อธิบายคำศัพท์ — โครงเดียวกับ _showInfoPopup ใน
// _SettingsScreenState แต่ทำเป็นฟังก์ชันแยกเพราะหน้านี้อยู่คนละ State class
void _showRateInfoDialog(
    BuildContext context, String title, String message) {
  showInfoDialog(context, title: title, message: message);
}

// การ์ดสีขาวมาตรฐาน — โทนเดียวกับการ์ดอื่นๆ ในหน้าตั้งค่าทั้งแอป
Widget _rateCard({required Widget child}) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withValues(alpha: 0.1),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

// หัวข้อของแต่ละการ์ด: ไอคอน + ชื่อหัวข้อ + ปุ่ม (i) ถ้ามีคำอธิบายเพิ่ม
Widget _rateCardHeader({
  required BuildContext context,
  required IconData icon,
  required String title,
  required Color color,
  String? infoTitle,
  String? infoMessage,
}) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
      if (infoTitle != null && infoMessage != null)
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.info_outline, color: color, size: 20),
          onPressed: () =>
              _showRateInfoDialog(context, infoTitle, infoMessage),
        ),
    ],
  );
}

// แถวในตารางขั้นบันได: ช่วงหน่วย + ราคาต่อหน่วย — สลับสีพื้นหลังให้อ่านง่าย
Widget _tierRow({
  required String range,
  required String pricePerUnit,
  required bool isAlt,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    color: isAlt ? color.withValues(alpha: 0.05) : Colors.transparent,
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(range, style: const TextStyle(fontSize: 12.5)),
        ),
        Expanded(
          flex: 2,
          child: Text(
            pricePerUnit,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

// ป้ายบอกว่ากำลังดูอัตราของเกณฑ์ไหนอยู่ — ดึงจาก area/meterType ที่ผู้ใช้
// ตั้งไว้จริงในโปรไฟล์ ไม่ใช่ให้เลือกเองในหน้านี้ เพื่อไม่ให้สับสนกับ
// อัตราที่แอปใช้คำนวณบิลจริงให้อยู่แล้ว
Widget _currentSettingBanner({
  required IconData icon,
  required String label,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
                color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

// ==================== แท็บไฟฟ้า ====================
class _ElectricityRateTab extends StatefulWidget {
  final String area;
  final String meterType;

  const _ElectricityRateTab({required this.area, required this.meterType});

  @override
  State<_ElectricityRateTab> createState() => _ElectricityRateTabState();
}

class _ElectricityRateTabState extends State<_ElectricityRateTab> {
  static const _amber = Color(0xFFF9A825);
  static const _green = Color(0xFF2E7D32);
  double? _ftRate;

  @override
  void initState() {
    super.initState();
    _loadFtRate();
  }

  // ดึงค่า Ft ปัจจุบันจาก app_config/electricity_rates เหมือนที่
  // EnergyCalculator ใช้คำนวณบิลจริง เพื่อให้ตัวเลขที่โชว์ตรงกับที่แอปใช้
  Future<void> _loadFtRate() async {
    final rate = await EnergyCalculator.getFtRate();
    if (mounted) setState(() => _ftRate = rate);
  }

  @override
  Widget build(BuildContext context) {
    final isTou = widget.meterType == 'tou';
    final isBangkok = widget.area == 'bangkok';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _currentSettingBanner(
          icon: Icons.bolt,
          color: _amber,
          label: isTou
              ? 'บัญชีของคุณตั้งค่าเป็นมิเตอร์ TOU (คิดตามช่วงเวลาการใช้ไฟ)'
              : '${isBangkok ? 'กรุงเทพฯ/นนทบุรี/สมุทรปราการ (การไฟฟ้านครหลวง - MEA)' : 'ต่างจังหวัด (การไฟฟ้าส่วนภูมิภาค - PEA)'} • มิเตอร์ปกติ',
        ),

        // 1) หลักการขั้นบันได / TOU
        _rateCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rateCardHeader(
                context: context,
                icon: Icons.trending_up_rounded,
                color: _amber,
                title: isTou
                    ? 'มิเตอร์ TOU คิดเงินยังไง'
                    : 'ทำไมยิ่งใช้ไฟเยอะ ยิ่งแพงขึ้น',
                infoTitle: isTou ? 'อัตรา TOU คืออะไร' : 'ระบบอัตราขั้นบันได',
                infoMessage: isTou
                    ? 'มิเตอร์ TOU คิดค่าไฟตามช่วงเวลาแทนปริมาณการใช้ '
                        'แบ่งเป็นช่วง Peak (ไฟแพง) และ Off-Peak (ไฟถูก) '
                        'ราคาต่อหน่วยคงที่ตลอดแต่ละช่วง ไม่ขยับตามจำนวน'
                        'หน่วยที่ใช้เหมือนมิเตอร์ปกติ'
                    : 'ค่าไฟฟ้าบ้านเรือนคิดแบบขั้นบันได หน่วยแรกราคาต่ำ '
                        'และราคาต่อหน่วยเพิ่มขึ้นเป็นช่วงตามจำนวนหน่วยที่'
                        'ใช้ทั้งเดือน',
              ),
            ],
          ),
        ),

        // 2) ตารางอัตรา
        _rateCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rateCardHeader(
                context: context,
                icon: Icons.table_chart_outlined,
                color: _green,
                title: isTou
                    ? 'อัตรา TOU (Peak / Off-Peak)'
                    : 'ตารางอัตราค่าไฟฟ้า',
                infoTitle: isTou
                    ? null
                    : (isBangkok
                        ? 'ระบบเซตไว้ยังไง (กทม./นนทบุรี/สมุทรปราการ)'
                        : 'ระบบเซตไว้ยังไง (ต่างจังหวัด)'),
                infoMessage: isTou
                    ? null
                    : (isBangkok
                        ? 'การไฟฟ้านครหลวง (MEA) แบ่งประเภทผู้ใช้ไฟตาม '
                            '"ขนาดมิเตอร์" ไม่ได้ดูจากจำนวนหน่วยที่ใช้ต่อ'
                            'เดือน — มิเตอร์ 5 แอมป์ จัดเป็นประเภท 1.1 '
                            'ส่วนมิเตอร์ 15 แอมป์ขึ้นไป จัดเป็นประเภท 1.2 '
                            'เสมอไม่ว่าจะใช้ไฟกี่หน่วยก็ตาม เนื่องจากบ้าน'
                            'ส่วนใหญ่ในปัจจุบันติดตั้งมิเตอร์ 15 แอมป์ขึ้นไป'
                            'กันแล้ว แอปจึงตั้งค่าคำนวณด้วยอัตราประเภท 1.2 '
                            '(ตารางที่เห็นด้านล่าง) ให้อัตโนมัติเลย'
                        : 'การไฟฟ้าส่วนภูมิภาค (PEA) แบ่งประเภทผู้ใช้ไฟตาม '
                            '"จำนวนหน่วยที่ใช้ต่อเดือน" — ใช้ไม่เกิน 150 '
                            'หน่วย จัดเป็นประเภท 1.1.1 ใช้เกิน 150 หน่วย '
                            'จัดเป็นประเภท 1.1.2 เนื่องจากบ้านส่วนใหญ่ในปัจจุบัน'
                            'มีทั้งแอร์และเครื่องทำน้ำอุ่น ทำให้ใช้ไฟเกิน 150 '
                            'หน่วยต่อเดือนอยู่แล้ว แอปจึงตั้งค่าคำนวณด้วยอัตรา'
                            'ประเภท 1.1.2 (ตารางที่เห็นด้านล่าง) ให้อัตโนมัติเลย'),
              ),
              const SizedBox(height: 8),
              if (isTou) ...[
                _tierRow(
                    range: 'ช่วง Peak (จ.-ศ. 09:00-22:00 น.)',
                    pricePerUnit: '5.7982 บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                _tierRow(
                    range: 'ช่วง Off-Peak (นอกเวลาข้างต้น)',
                    pricePerUnit: '2.6369 บาท/หน่วย',
                    isAlt: true,
                    color: _green),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '24.62 บาท',
                    isAlt: false,
                    color: _green),
              ] else if (isBangkok) ...[
                _tierRow(
                    range: '1 - 150 หน่วย',
                    pricePerUnit: '3.2484 บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                _tierRow(
                    range: '151 - 400 หน่วย',
                    pricePerUnit: '4.2218 บาท/หน่วย',
                    isAlt: true,
                    color: _green),
                _tierRow(
                    range: '401 หน่วยขึ้นไป',
                    pricePerUnit: '4.4217 บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '24.62 บาท',
                    isAlt: true,
                    color: _green),
              ] else ...[
                _tierRow(
                    range: '1 - 150 หน่วย',
                    pricePerUnit: '3.2484 บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                _tierRow(
                    range: '151 - 400 หน่วย',
                    pricePerUnit: '4.2218 บาท/หน่วย',
                    isAlt: true,
                    color: _green),
                _tierRow(
                    range: '401 หน่วยขึ้นไป',
                    pricePerUnit: '4.4217 บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '24.62 บาท',
                    isAlt: true,
                    color: _green),
              ],
            ],
          ),
        ),

        // 3) ค่า Ft
        _rateCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rateCardHeader(
                context: context,
                icon: Icons.show_chart,
                color: _amber,
                title: 'ค่า Ft คืออะไร',
                infoTitle: 'ค่า Ft (ค่าไฟฟ้าผันแปร)',
                infoMessage:
                    'ค่า Ft คือค่าไฟฟ้าที่ปรับขึ้น-ลงได้ตามต้นทุนค่าเชื้อ'
                    'เพลิงและค่าซื้อไฟจริงของการไฟฟ้าในแต่ละช่วง ประกาศ'
                    'ปรับใหม่ทุกๆ 4 เดือน โดยคิดคูณกับจำนวนหน่วยไฟที่ใช้'
                    'ทั้งหมด แอปจะดึงค่า Ft ล่าสุดที่แอดมินตั้งไว้มาใช้'
                    'คำนวณให้อัตโนมัติ ไม่ต้องกรอกเอง',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('ค่า Ft ที่แอปใช้อยู่ตอนนี้: ',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                  _ftRate == null
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _green),
                        )
                      : Text(
                          '${_ftRate!.toStringAsFixed(4)} บาท/หน่วย',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _green),
                        ),
                ],
              ),
            ],
          ),
        ),

        // 4) VAT
        _rateCard(
          child: _rateCardHeader(
            context: context,
            icon: Icons.percent,
            color: _green,
            title: 'ภาษีมูลค่าเพิ่ม (VAT) 7%',
            infoTitle: 'VAT คิดตรงไหน',
            infoMessage:
                'หลังจากรวม ค่าพลังงานไฟฟ้า + ค่าบริการรายเดือน + ค่า Ft '
                'เข้าด้วยกันแล้ว จะนำยอดรวมทั้งหมดนั้นมาคูณ VAT 7% อีกที'
                ' เป็นขั้นตอนสุดท้ายก่อนได้ยอดบิลที่ต้องจ่ายจริง',
          ),
        ),
      ],
    );
  }
}

// ==================== แท็บน้ำ ====================
class _WaterRateTab extends StatelessWidget {
  final String area;

  const _WaterRateTab({required this.area});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0288D1);
    const green = Color(0xFF2E7D32);
    final isBangkok = area == 'bangkok';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _currentSettingBanner(
          icon: Icons.water_drop,
          color: blue,
          label: isBangkok
              ? 'กรุงเทพฯ/นนทบุรี/สมุทรปราการ (การประปานครหลวง - MWA)'
              : 'ต่างจังหวัด (การประปาส่วนภูมิภาค - PWA)',
        ),

        _rateCard(
          child: _rateCardHeader(
            context: context,
            icon: Icons.trending_up_rounded,
            color: blue,
            title: 'ค่าน้ำก็คิดแบบขั้นบันไดเหมือนกัน',
            infoTitle: 'ระบบอัตราขั้นบันได',
            infoMessage:
                'ยิ่งใช้น้ำเยอะ หน่วยที่เกินมาก็จะถูกคิดในอัตราที่สูงขึ้น'
                'เรื่อยๆ เหมือนหลักการของค่าไฟฟ้าเลย ไม่ได้คิดราคา'
                'เดียวทั้งบิล',
          ),
        ),

        _rateCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rateCardHeader(
                context: context,
                icon: Icons.table_chart_outlined,
                color: blue,
                title: 'ตารางอัตราค่าน้ำ',
              ),
              const SizedBox(height: 8),
              if (isBangkok) ...[
                _tierRow(
                    range: '1 - 30 หน่วย',
                    pricePerUnit: '8.50 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '31 - 40 หน่วย',
                    pricePerUnit: '10.03 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '41 - 50 หน่วย',
                    pricePerUnit: '10.35 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '51 - 60 หน่วย',
                    pricePerUnit: '10.68 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '61 - 70 หน่วย',
                    pricePerUnit: '11.00 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '71 - 80 หน่วย',
                    pricePerUnit: '11.33 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '81 - 90 หน่วย',
                    pricePerUnit: '12.50 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '91 - 100 หน่วย',
                    pricePerUnit: '12.82 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '101 - 120 หน่วย',
                    pricePerUnit: '13.15 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '121 - 160 หน่วย',
                    pricePerUnit: '13.47 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '161 - 200 หน่วย',
                    pricePerUnit: '13.80 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '201 หน่วยขึ้นไป',
                    pricePerUnit: '14.45 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '25.00 บาท',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: 'ค่าน้ำดิบ',
                    pricePerUnit: '0.15 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
              ] else ...[
                Text('ที่อยู่อาศัย ใช้ไม่เกิน 50 หน่วย:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
                _tierRow(
                    range: '1 - 10 หน่วยแรก',
                    pricePerUnit: '10.20 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '11 - 20 หน่วย',
                    pricePerUnit: '16.00 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '21 - 30 หน่วย',
                    pricePerUnit: '19.00 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '31 - 50 หน่วย',
                    pricePerUnit: '21.20 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                const Divider(height: 20),
                Text('ใช้เกิน 50 หน่วย (หน่วยที่ 51 ขึ้นไปคิดอัตรานี้แทน):',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
                _tierRow(
                    range: '51 - 80 หน่วย',
                    pricePerUnit: '21.60 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '81 - 100 หน่วย',
                    pricePerUnit: '21.65 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '101 - 300 หน่วย',
                    pricePerUnit: '21.70 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '301 - 1,000 หน่วย',
                    pricePerUnit: '21.75 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '1,001 - 2,000 หน่วย',
                    pricePerUnit: '21.80 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '2,001 - 3,000 หน่วย',
                    pricePerUnit: '21.85 บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '3,001 หน่วยขึ้นไป',
                    pricePerUnit: '21.90 บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '30.00 บาท',
                    isAlt: true,
                    color: blue),
              ],
            ],
          ),
        ),

        _rateCard(
          child: _rateCardHeader(
            context: context,
            icon: Icons.vertical_align_bottom,
            color: blue,
            title: 'ค่าน้ำขั้นต่ำต่อเดือน',
            infoTitle: 'ค่าน้ำขั้นต่ำคืออะไร',
            infoMessage: isBangkok
                ? 'ถ้าเดือนไหนใช้น้ำน้อยมากจนคำนวณตามขั้นบันไดแล้วได้ยอด'
                    'ต่ำกว่า 45 บาท (ก่อน VAT) การประปานครหลวงจะเรียกเก็บ'
                    'ขั้นต่ำที่ 45 บาทแทน'
                : 'ถ้าเดือนไหนใช้น้ำน้อยมากจนคำนวณตามขั้นบันไดแล้วได้ยอด'
                    'ต่ำกว่า 50 บาท (ก่อน VAT) การประปาส่วนภูมิภาคจะเรียก'
                    'เก็บขั้นต่ำที่ 50 บาทแทน',
          ),
        ),

        _rateCard(
          child: _rateCardHeader(
            context: context,
            icon: Icons.percent,
            color: green,
            title: 'ภาษีมูลค่าเพิ่ม (VAT) 7%',
            infoTitle: 'VAT คิดตรงไหน',
            infoMessage:
                'หลังจากรวมค่าน้ำตามขั้นบันได + ค่าบริการรายเดือน'
                '${isBangkok ? " + ค่าน้ำดิบ" : ""} แล้ว (หรือใช้ยอดขั้นต่ำ'
                'แทนถ้าคำนวณได้ต่ำกว่า) จะนำยอดรวมมาคูณ VAT 7% อีกที'
                ' เป็นขั้นตอนสุดท้ายก่อนได้ยอดบิลที่ต้องจ่ายจริง',
          ),
        ),
      ],
    );
  }
}