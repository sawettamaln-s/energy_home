part of 'settings_screen.dart';

// ==================== อธิบายอัตราค่าไฟฟ้า / น้ำ ====================
// หน้า static content ล้วนๆ (ยกเว้นค่า Ft ที่ดึงสดจาก Firestore) ไม่มีการบันทึก/แก้ไขข้อมูล
// แค่โชว์ตารางอัตรา + คำอธิบายตามพื้นที่และประเภทมิเตอร์ที่ผู้ใช้ตั้งไว้จริง
class _RateExplanationScreen extends StatefulWidget {
  final String area; // 'bangkok' (MEA/MWA) หรือ 'province' (PEA/PWA)
  final String meterType; // 'normal' หรือ 'tou'
  final String tariff; // ประเภทอัตราของมิเตอร์ปกติ (UserModel.electricityTariff)

  const _RateExplanationScreen({
    required this.area,
    required this.meterType,
    required this.tariff,
  });

  @override
  State<_RateExplanationScreen> createState() =>
      _RateExplanationScreenState();
}

class _RateExplanationScreenState extends State<_RateExplanationScreen>
    with SingleTickerProviderStateMixin {
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
      backgroundColor: DashboardStyles.background,
      appBar: AppTopBar(
        title: 'อัตราค่าไฟฟ้า / น้ำ',
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
          _ElectricityRateTab(
              area: widget.area,
              meterType: widget.meterType,
              tariff: widget.tariff),
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
    margin: const EdgeInsets.only(bottom: AppSpacing.v12),
    padding: const EdgeInsets.all(AppSpacing.v16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppSpacing.v12),
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
        padding: const EdgeInsets.all(AppSpacing.v8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.v8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.s15),
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
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v10, vertical: AppSpacing.v8),
    color: isAlt ? color.withValues(alpha: 0.05) : Colors.transparent,
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(range, style: const TextStyle(fontSize: AppTypography.s12_5)),
        ),
        Expanded(
          flex: 2,
          child: Text(
            pricePerUnit,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: AppTypography.s12_5,
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
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v12, vertical: AppSpacing.v10),
    margin: const EdgeInsets.only(bottom: AppSpacing.v12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.v10),
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
                color: color, fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

// ข้อความย่อหน้าในการ์ด — สีเทาเข้ม อ่านง่าย
Widget _rateBody(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.v8),
      child: Text(text,
          style: TextStyle(
              fontSize: AppTypography.s12_5,
              color: Colors.grey.shade800,
              height: 1.5)),
    );

// 1 ประเภทอัตราในการ์ด "ประเภทอัตรา" — ไฮไลต์ประเภทที่แอปใช้คิดให้ผู้ใช้อยู่
Widget _tariffTypeRow({
  required String code,
  required String title,
  required String detail,
  required bool inUse,
  required Color color,
}) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: AppSpacing.v8),
    padding: const EdgeInsets.all(AppSpacing.v10),
    decoration: BoxDecoration(
      color: inUse ? color.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(AppSpacing.v10),
      border: Border.all(
          color: inUse ? color : Colors.grey.shade300, width: inUse ? 1.5 : 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('ประเภท $code',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTypography.s13,
                    color: color)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: AppTypography.s12_5)),
            ),
            if (inUse)
              Text('แอปใช้อยู่',
                  style: TextStyle(
                      fontSize: AppTypography.s11,
                      fontWeight: FontWeight.bold,
                      color: color)),
          ],
        ),
        const SizedBox(height: 4),
        Text(detail,
            style: TextStyle(
                fontSize: AppTypography.s12,
                color: Colors.grey.shade700,
                height: 1.4)),
      ],
    ),
  );
}

// การ์ดแหล่งอ้างอิงอัตรา (ข้อความล้วน กดลิงก์ไม่ได้) พร้อมวันที่ตรวจล่าสุด
Widget _rateSourcesCard(BuildContext context, List<String> sources) {
  return _rateCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rateCardHeader(
          context: context,
          icon: Icons.verified_outlined,
          color: Colors.grey.shade700,
          title: 'แหล่งอ้างอิงอัตรา',
        ),
        _rateBody('ตรวจกับประกาศทางการล่าสุดเมื่อ 3 ต.ค. 2569\n'
            '${sources.map((s) => '• $s').join('\n')}'),
      ],
    ),
  );
}

// ==================== แท็บไฟฟ้า ====================
class _ElectricityRateTab extends StatefulWidget {
  final String area;
  final String meterType;
  final String tariff;

  const _ElectricityRateTab({
    required this.area,
    required this.meterType,
    required this.tariff,
  });

  @override
  State<_ElectricityRateTab> createState() => _ElectricityRateTabState();
}

class _ElectricityRateTabState extends State<_ElectricityRateTab> {
  static const _amber = AppColors.rateHighlight;
  static const _green = DashboardStyles.primaryGreen;
  FtInfo? _ft;

  @override
  void initState() {
    super.initState();
    _loadFtRate();
  }

  // ดึงค่า Ft ปัจจุบันจาก app_config/electricity_rates เหมือนที่
  // EnergyCalculator ใช้คำนวณบิลจริง เพื่อให้ตัวเลขที่โชว์ตรงกับที่แอปใช้
  Future<void> _loadFtRate() async {
    final ft = await EnergyCalculator.getFtInfo();
    if (mounted) setState(() => _ft = ft);
  }

  @override
  Widget build(BuildContext context) {
    final isTou = widget.meterType == 'tou';
    final isBangkok = widget.area == 'bangkok';
    final isSmall = widget.tariff == EnergyCalculator.tariffSmall;
    final area = widget.area;
    final smallCode =
        EnergyCalculator.tariffCode(EnergyCalculator.tariffSmall, area);
    final standardCode =
        EnergyCalculator.tariffCode(EnergyCalculator.tariffStandard, area);
    final touCode = EnergyCalculator.touCode(area);
    final ftOutdated = _ft != null &&
        EnergyCalculator.isFtOutdated(_ft!.effectiveFrom, DateTime.now());

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.v16),
      children: [
        _currentSettingBanner(
          icon: Icons.bolt,
          color: _amber,
          label: isTou
              ? 'บัญชีของคุณตั้งค่าเป็นมิเตอร์ TOU (คิดตามช่วงเวลาการใช้ไฟ)'
              : '${isBangkok ? 'กรุงเทพฯ/นนทบุรี/สมุทรปราการ (การไฟฟ้านครหลวง - MEA)' : 'ต่างจังหวัด (การไฟฟ้าส่วนภูมิภาค - PEA)'} • มิเตอร์ปกติ ${isSmall ? 'ประเภท $smallCode' : 'ประเภท $standardCode'}',
        ),

        // 0) ประเภทอัตราบ้านอยู่อาศัยของการไฟฟ้าในพื้นที่ผู้ใช้
        _rateCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rateCardHeader(
                context: context,
                icon: Icons.category_outlined,
                color: _green,
                title: 'ประเภทอัตราค่าไฟบ้านอยู่อาศัย',
              ),
              _rateBody('ประเภทที่ใช้คิดเงินพิมพ์อยู่บนใบแจ้งหนี้ค่าไฟทุกใบ '
                  '${isBangkok ? 'การไฟฟ้านครหลวง' : 'การไฟฟ้าส่วนภูมิภาค'}'
                  'แบ่งบ้านอยู่อาศัยเป็น 3 ประเภท:'),
              _tariffTypeRow(
                code: smallCode,
                title: 'ใช้ไม่เกิน 150 หน่วย/เดือน',
                detail: 'เฉพาะมิเตอร์ไม่เกิน 5 แอมแปร์ อัตราถูกกว่า ค่าบริการ '
                    '${EnergyCalculator.smallServiceFee.toStringAsFixed(2)} บาท/เดือน',
                inUse: !isTou && isSmall,
                color: _green,
              ),
              _tariffTypeRow(
                code: standardCode,
                title: 'ใช้เกิน 150 หน่วย/เดือน',
                detail: 'บ้านส่วนใหญ่ (มิเตอร์ใหญ่กว่า 5 แอมแปร์จัดอยู่ประเภทนี้เสมอ) '
                    'ค่าบริการ ${EnergyCalculator.electricityServiceFee.toStringAsFixed(2)} '
                    'บาท/เดือน — ค่าเริ่มต้นของแอป',
                inUse: !isTou && !isSmall,
                color: _green,
              ),
              _tariffTypeRow(
                code: touCode,
                title: 'TOU คิดตามช่วงเวลา',
                detail: 'ต้องติดตั้งมิเตอร์ TOU แอปใช้อัตราแรงดันต่ำกว่า '
                    '${isBangkok ? '12' : '22'} kV ซึ่งเป็นของบ้านทั่วไป',
                inUse: isTou,
                color: _green,
              ),
              _rateBody('กติกาการเปลี่ยนประเภท (มิเตอร์ไม่เกิน 5 แอมแปร์): ใช้เกิน '
                  '150 หน่วยติดต่อกัน 3 เดือน เดือนถัดไปเป็นประเภท $standardCode '
                  'และใช้ไม่เกิน 150 หน่วยติดต่อกัน 3 เดือน กลับเป็นประเภท $smallCode '
                  '— ถ้าบิลของคุณเข้าเงื่อนไข แอปจะขึ้นแจ้งให้ตรวจ\n\n'
                  'เปลี่ยนประเภทให้ตรงใบแจ้งหนี้ได้ที่ ตั้งค่า > ประเภทอัตราค่าไฟ\n\n'
                  'สิทธิ์ไฟฟรีไม่เกิน 50 หน่วยของผู้ถือบัตรสวัสดิการแห่งรัฐที่ลงทะเบียน'
                  'ไว้ แอปไม่ได้หักให้'),
            ],
          ),
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
              ),
              _rateBody(isTou
                  ? 'ประเภท $touCode'
                  : 'ประเภท ${isSmall ? smallCode : standardCode} ที่แอปใช้คิดให้คุณอยู่'),
              const SizedBox(height: 8),
              if (isTou) ...[
                _tierRow(
                    range: 'ช่วง Peak (จ.-ศ. 09:00-22:00 น. ไม่รวมวันหยุดราชการ)',
                    pricePerUnit: '${EnergyCalculator.touPeakRate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                _tierRow(
                    range: 'ช่วง Off-Peak (นอกเวลาข้างต้น เสาร์-อาทิตย์ และวันหยุดราชการ)',
                    pricePerUnit: '${EnergyCalculator.touOffPeakRate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: true,
                    color: _green),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '${EnergyCalculator.electricityServiceFee.toStringAsFixed(2)} บาท',
                    isAlt: false,
                    color: _green),
              ] else if (isSmall) ...[
                _tierRow(
                    range: '1 - 15 หน่วย',
                    pricePerUnit: '${EnergyCalculator.smallTier1Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                _tierRow(
                    range: '16 - 25 หน่วย',
                    pricePerUnit: '${EnergyCalculator.smallTier2Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: true,
                    color: _green),
                _tierRow(
                    range: '26 - 35 หน่วย',
                    pricePerUnit: '${EnergyCalculator.smallTier3Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                _tierRow(
                    range: '36 - 100 หน่วย',
                    pricePerUnit: '${EnergyCalculator.smallTier4Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: true,
                    color: _green),
                _tierRow(
                    range: '101 - 150 หน่วย',
                    pricePerUnit: '${EnergyCalculator.smallTier5Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                _tierRow(
                    range: '151 - 400 หน่วย',
                    pricePerUnit: '${EnergyCalculator.smallTier6Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: true,
                    color: _green),
                _tierRow(
                    range: '401 หน่วยขึ้นไป',
                    pricePerUnit: '${EnergyCalculator.smallTier7Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '${EnergyCalculator.smallServiceFee.toStringAsFixed(2)} บาท',
                    isAlt: true,
                    color: _green),
              ] else ...[
                _tierRow(
                    range: '1 - 150 หน่วย',
                    pricePerUnit: '${EnergyCalculator.electricityTier1Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                _tierRow(
                    range: '151 - 400 หน่วย',
                    pricePerUnit: '${EnergyCalculator.electricityTier2Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: true,
                    color: _green),
                _tierRow(
                    range: '401 หน่วยขึ้นไป',
                    pricePerUnit: '${EnergyCalculator.electricityTier3Rate.toStringAsFixed(4)} บาท/หน่วย',
                    isAlt: false,
                    color: _green),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '${EnergyCalculator.electricityServiceFee.toStringAsFixed(2)} บาท',
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
                    'เพลิงและค่าซื้อไฟจริงของการไฟฟ้าในแต่ละช่วง คณะกรรมการ'
                    'กำกับกิจการพลังงาน (กกพ.) ประกาศใหม่ทุก 4 เดือน (งวด '
                    'ม.ค.-เม.ย., พ.ค.-ส.ค., ก.ย.-ธ.ค.) คิดคูณกับจำนวนหน่วยไฟ'
                    'ที่ใช้ทั้งหมด แอปดึงค่า Ft ที่ผู้ดูแลระบบตั้งไว้มาคำนวณ'
                    'ให้อัตโนมัติ ไม่ต้องกรอกเอง',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('ค่า Ft ที่แอปใช้อยู่ตอนนี้: ',
                      style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey)),
                  _ft == null
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _green),
                        )
                      : Text(
                          '${_ft!.rate.toStringAsFixed(4)} บาท/หน่วย',
                          style: const TextStyle(
                              fontSize: AppTypography.s12_5,
                              fontWeight: FontWeight.bold,
                              color: _green),
                        ),
                ],
              ),
              if (_ft?.effectiveFrom != null)
                _rateBody('ใช้กับงวดที่เริ่ม '
                    '${_ft!.effectiveFrom!.day} ${thaiMonths[_ft!.effectiveFrom!.month - 1]} '
                    '${_ft!.effectiveFrom!.year + 543}'),
              // งวดที่ตั้งไว้เก่ากว่า 4 เดือน = ยังไม่ได้อัปเดตงวดใหม่ ยอดอาจคลาด
              if (ftOutdated)
                Container(
                  margin: const EdgeInsets.only(top: AppSpacing.v8),
                  padding: const EdgeInsets.all(AppSpacing.v8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppSpacing.v8),
                  ),
                  child: Text(
                    'ค่า Ft งวดใหม่อาจยังไม่ได้อัปเดตในแอป ยอดค่าไฟที่คำนวณ'
                    'อาจคลาดจากบิลจริงเล็กน้อยค่ะ',
                    style: TextStyle(
                        fontSize: AppTypography.s12,
                        color: Colors.orange.shade900),
                  ),
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

        _rateSourcesCard(context, [
          isBangkok
              ? 'อัตราไฟฟ้า: กกพ. erc.or.th/th/tariff/1288'
              : 'อัตราไฟฟ้า: กฟภ. ประกาศอัตราค่าไฟฟ้า (pea.co.th)',
          'ค่า Ft: กกพ. erc.or.th (ประกาศทุก 4 เดือน)',
        ]),
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
    const blue = AppColors.rateWater;
    const green = DashboardStyles.primaryGreen;
    final isBangkok = area == 'bangkok';

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.v16),
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
                title: 'ตารางอัตราค่าน้ำ (ประเภทที่อยู่อาศัย)',
              ),
              if (!isBangkok)
                _rateBody('ตารางหมายเลข 3 ของ กปภ. ซึ่งใช้กับสาขาส่วนใหญ่ทั่วประเทศ '
                    '(บางสาขา เช่น ชลบุรี พัทยา ระยอง ปทุมธานี ภูเก็ต เกาะสมุย '
                    'ใช้ตารางอื่นที่หน่วยเกิน 50 แพงกว่านี้)'),
              const SizedBox(height: 8),
              if (isBangkok) ...[
                _tierRow(
                    range: '1 - 30 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier1.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '31 - 40 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier2.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '41 - 50 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier3.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '51 - 60 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier4.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '61 - 70 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier5.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '71 - 80 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier6.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '81 - 90 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier7.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '91 - 100 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier8.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '101 - 120 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier9.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '121 - 160 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier10.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '161 - 200 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier11.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '201 หน่วยขึ้นไป',
                    pricePerUnit: '${EnergyCalculator.waterMwaTier12.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '${EnergyCalculator.waterMwaServiceFee.toStringAsFixed(2)} บาท',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: 'ค่าน้ำดิบ',
                    pricePerUnit: '${EnergyCalculator.waterMwaRawWaterFee.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
              ] else ...[
                Text('ที่อยู่อาศัย ใช้ไม่เกิน 50 หน่วย:',
                    style: TextStyle(
                        fontSize: AppTypography.s12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
                _tierRow(
                    range: '1 - 10 หน่วยแรก',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier1.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '11 - 20 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier2.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '21 - 30 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier3.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '31 - 50 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier4.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                const Divider(height: 20),
                Text('ใช้เกิน 50 หน่วย (หน่วยที่ 51 ขึ้นไปคิดอัตรานี้แทน):',
                    style: TextStyle(
                        fontSize: AppTypography.s12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
                _tierRow(
                    range: '51 - 80 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier5.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '81 - 100 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier6.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '101 - 300 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier7.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '301 - 1,000 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier8.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '1,001 - 2,000 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier9.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                _tierRow(
                    range: '2,001 - 3,000 หน่วย',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier10.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: true,
                    color: blue),
                _tierRow(
                    range: '3,001 หน่วยขึ้นไป',
                    pricePerUnit: '${EnergyCalculator.waterPwaTier11.toStringAsFixed(2)} บาท/หน่วย',
                    isAlt: false,
                    color: blue),
                const Divider(height: 20),
                _tierRow(
                    range: 'ค่าบริการรายเดือน',
                    pricePerUnit: '${EnergyCalculator.waterPwaServiceFee.toStringAsFixed(2)} บาท',
                    isAlt: true,
                    color: blue),
              ],
            ],
          ),
        ),

        _rateCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rateCardHeader(
                context: context,
                icon: Icons.speed_outlined,
                color: blue,
                title: 'ค่าบริการตามขนาดมาตรวัดน้ำ',
              ),
              _rateBody('ค่าบริการรายเดือนขึ้นกับขนาดมาตรวัดน้ำ แอปใช้ขนาด ½ นิ้ว '
                  'ของบ้านทั่วไป (${(isBangkok ? EnergyCalculator.waterMwaServiceFee : EnergyCalculator.waterPwaServiceFee).toStringAsFixed(0)} บาท/เดือน) '
                  'ถ้าบ้านคุณใช้มาตรใหญ่กว่านี้ ค่าบริการจริงจะสูงกว่า\n\n'
                  'ประเภทที่อยู่อาศัยไม่มีค่าน้ำขั้นต่ำ ใช้น้อยก็จ่ายตามจริง'
                  '${isBangkok ? ' (กปน. ยกเลิกค่าน้ำขั้นต่ำตั้งแต่ เม.ย. 2558)' : ''}'),
            ],
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
                '${isBangkok ? " + ค่าน้ำดิบ" : ""} แล้ว จะนำยอดรวมมาคูณ '
                'VAT 7% อีกที เป็นขั้นตอนสุดท้ายก่อนได้ยอดบิลที่ต้องจ่ายจริง',
          ),
        ),

        _rateSourcesCard(context, [
          isBangkok
              ? 'อัตราค่าน้ำ: กปน. mwa.co.th (อัตราค่าน้ำและบริการ)'
              : 'อัตราค่าน้ำ: กปภ. pwa.co.th (อัตราค่าน้ำประปาส่วนภูมิภาค)',
        ]),
      ],
    );
  }
}