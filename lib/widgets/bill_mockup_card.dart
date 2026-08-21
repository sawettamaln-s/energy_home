import 'package:flutter/material.dart';

import '../screens/dashboard/dashboard_styles.dart';

/// ===========================================================
/// BillMockupCard
/// ===========================================================
/// การ์ดตัวอย่างบิลไฟฟ้า/น้ำ (mock) ใช้ประกอบ popup "กรอกตรงไหนของบิล?"
/// ในหน้าบันทึกเลขมิเตอร์ประจำเดือน ช่วยให้ผู้ใช้เทียบตำแหน่งตัวเลขบนบิล
/// จริงกับช่องกรอกในแอปได้ง่ายขึ้น
///
/// เลือกผู้ให้บริการอัตโนมัติจาก area ของผู้ใช้ (ตั้งค่าตอนสมัคร):
///   - 'bangkok'  -> ไฟฟ้า MEA (การไฟฟ้านครหลวง) / น้ำ MWA (การประปานครหลวง)
///   - 'province' -> ไฟฟ้า PEA (การไฟฟ้าส่วนภูมิภาค) / น้ำ PWA (การประปาส่วนภูมิภาค)
/// ฝั่งไฟฟ้าเลือกโครงสร้างตาราง TOU (On-Peak/Off-Peak) หรือปกติ ตาม isTou
///
/// ตัวเลขในการ์ดเป็นข้อมูลตัวอย่างล้วน (mock) ไม่ผูกกับข้อมูลจริงของผู้ใช้
/// — เจตนาให้เห็นแค่ "ตำแหน่ง"/"คำศัพท์" ของแต่ละค่าบนบิล ไม่ใช่คำนวณยอดจริง
/// โครงสร้าง (ชื่อผู้ใช้/สถานที่/ตารางบัญชี/ตารางมิเตอร์/รายการค่าใช้จ่าย)
/// อิงตามบิลจริงของ MEA/MWA ที่ผู้ใช้ส่งมาเทียบ ให้ครบครันใกล้เคียงบิลจริง
class BillMockupCard extends StatelessWidget {
  final bool isElectricity;
  final String area; // 'bangkok' หรือ 'province'
  final bool isTou; // ใช้เฉพาะฝั่งไฟฟ้า

  // เมื่อ true จะล้อมกรอบสีแดงที่ช่อง "จำนวนหน่วย/จำนวนน้ำใช้" เพิ่มจาก
  // ช่องเลขอ่านครั้งหลัง (ซึ่งล้อมอยู่แล้วเป็นค่า default) — ใช้ตอนป๊อปอัพ
  // นี้เปิดมาคู่กับช่อง "หน่วยที่ใช้ไปแล้ว" ของการตั้งค่าครั้งแรกสุด เพื่อชี้
  // ให้ผู้ใช้เห็นว่าต้องเทียบกรอกทั้ง 2 ช่องบนบิลจริง ไม่ใช่แค่ช่องเดียว
  final bool highlightUsed;

  // เมื่อ false จะไม่ล้อมกรอบสีแดงที่ช่อง "เลขอ่านครั้งหลัง" (ค่า default คือ
  // true เพื่อคงพฤติกรรมเดิมของ popup หน้าบันทึกมิเตอร์ประจำเดือน) — ใช้ตอน
  // popup ต้องการชี้เฉพาะช่อง "จำนวนหน่วยที่ใช้" อย่างเดียว เช่นฟอร์มเพิ่ม/
  // แก้ไขบิลเดือนเก่า ที่ไม่รับกรอกเลขมิเตอร์สะสมเลย การล้อมกรอบเลขอ่านครั้ง
  // หลังไว้ด้วยจะชี้ผิดจุดและขัดกับคำเตือนในฟอร์มนั้น
  final bool highlightReading;

  const BillMockupCard({
    super.key,
    required this.isElectricity,
    required this.area,
    this.isTou = false,
    this.highlightUsed = false,
    this.highlightReading = true,
  });

  bool get _isBangkok => area == 'bangkok';

  Color get _accent =>
      isElectricity ? DashboardStyles.electricityBorder : DashboardStyles.waterBorder;

  @override
  Widget build(BuildContext context) {
    final data = _mockDataFor();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  data.logoLabel,
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: _accent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.providerName,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(data.providerSubtitle,
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(data.customerNameLine,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
          const SizedBox(height: 2),
          Text(data.premiseLine,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
          if (data.typeLine != null) ...[
            const SizedBox(height: 2),
            Text(data.typeLine!,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 10),
          _infoTable([data.accountRow], headerRow: data.accountHeader),
          const SizedBox(height: 8),
          _infoTable(
            data.meterRows,
            headerRow: data.meterHeader,
            highlightCols: {
              if (highlightReading) data.readingColIndex,
              if (highlightUsed) data.usedColIndex,
            },
          ),
          if (data.footnote != null) ...[
            const SizedBox(height: 4),
            Text(data.footnote!,
                style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500)),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              children: [
                for (final line in data.costLines) _costRow(line.$1, line.$2),
                const SizedBox(height: 4),
                _costRow(data.totalLabel, data.totalValue, bold: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ข้อมูลตัวอย่าง (mock) เพื่อการอ้างอิงโครงสร้างเท่านั้น ไม่ใช่เอกสารจริงของ ${data.providerAbbr}',
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _costRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: bold ? 12.5 : 11.5,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                      color: bold ? DashboardStyles.textDark : Colors.grey.shade700)),
            ),
            Text(value,
                style: TextStyle(
                    fontSize: bold ? 12.5 : 11.5,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                    color: bold ? DashboardStyles.textDark : Colors.grey.shade800)),
          ],
        ),
      );

  // highlightCols: ดัชนีคอลัมน์ (นับเฉพาะแถวข้อมูล ไม่รวมแถว header) ที่จะ
  // ล้อมกรอบสีแดงไว้ ใช้ชี้ตำแหน่งตัวเลขบนบิลจริงที่ผู้ใช้ต้องเทียบมากรอก
  // (ดูตัวอย่างกรอบแดงในบิลอ้างอิงที่ผู้ใช้ส่งมา)
  Widget _infoTable(List<List<String>> rows,
      {List<String>? headerRow, Set<int>? highlightCols}) {
    final allRows = [if (headerRow != null) headerRow, ...rows];
    final headerOffset = headerRow != null ? 1 : 0;
    return Table(
      columnWidths: {
        for (int i = 0; i < allRows.first.length; i++)
          i: const FlexColumnWidth(1),
      },
      children: [
        for (int r = 0; r < allRows.length; r++)
          TableRow(
            decoration: r == 0 && headerRow != null
                ? BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200)))
                : null,
            children: [
              for (int c = 0; c < allRows[r].length; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 3),
                  child: Builder(builder: (context) {
                    final isHighlighted = r >= headerOffset &&
                        (highlightCols?.contains(c) ?? false);
                    final text = Text(
                      allRows[r][c],
                      style: TextStyle(
                        fontSize: r == 0 && headerRow != null ? 9.5 : 11,
                        fontWeight:
                            isHighlighted ? FontWeight.w700 : FontWeight.normal,
                        color: r == 0 && headerRow != null
                            ? Colors.grey.shade500
                            : DashboardStyles.textDark,
                      ),
                    );
                    if (!isHighlighted) return text;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red, width: 1.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: text,
                    );
                  }),
                ),
            ],
          ),
      ],
    );
  }

  _BillMockData _mockDataFor() {
    if (isElectricity) {
      return _isBangkok
          ? (isTou ? _meaTouData() : _meaData())
          : (isTou ? _peaTouData() : _peaData());
    }
    return _isBangkok ? _mwaData() : _pwaData();
  }

  _BillMockData _meaData() => _BillMockData(
        logoLabel: 'MEA',
        providerName: 'การไฟฟ้านครหลวง (มอคอัพ)',
        providerSubtitle: 'ใบแจ้งค่าไฟฟ้า · MEA Call Center 1130',
        providerAbbr: 'MEA',
        customerNameLine: 'ชื่อผู้ใช้ไฟฟ้า (Name): นายตัวอย่าง เมืองดี',
        premiseLine:
            'สถานที่ใช้ไฟฟ้า (Premise): 88/8 ซอยสมมติ แขวงทดสอบ เขตตัวอย่าง กรุงเทพฯ',
        accountHeader: const [
          'บัญชีแสดงสัญญา (CA)',
          'รหัสเครื่องวัด (Installation)',
          'เลขที่ใบแจ้ง (Invoice No.)',
          'ประเภท (Type)',
        ],
        accountRow: const ['1122334455', 'ME00789', 'MOCK-000004', '1.2'],
        meterHeader: const [
          'เลขอ่านครั้งหลัง (Last Meter Reading)',
          'เลขอ่านครั้งก่อน (Previous Meter Reading)',
          'จำนวนหน่วย (kWh)',
          'ตัวคูณ (Multiplier)',
        ],
        meterRows: const [
          ['3,593', '3,493', '100', '1'],
        ],
        costLines: const [
          ('ค่าพลังงานไฟฟ้า', '324.80'),
          ('ค่าบริการ', '38.22'),
          ('ค่าไฟฟ้าผันแปร (Ft) -0.1160 บาท/หน่วย', '-11.60'),
          ('ส่วนลด', '0.00'),
          ('รวมค่าไฟฟ้าก่อนภาษีมูลค่าเพิ่ม', '351.42'),
          ('ภาษีมูลค่าเพิ่ม 7%', '24.60'),
        ],
        totalLabel: 'รวมค่าไฟฟ้าเดือนปัจจุบัน',
        totalValue: '376.02',
      );

  _BillMockData _peaData() => _BillMockData(
        logoLabel: 'PEA',
        providerName: 'การไฟฟ้าส่วนภูมิภาค (มอคอัพ)',
        providerSubtitle: 'ใบแจ้งค่าไฟฟ้า · PEA Contact Center 1129',
        providerAbbr: 'PEA',
        customerNameLine: 'ชื่อผู้ใช้ไฟฟ้า (Name): นายตัวอย่าง เมืองดี',
        premiseLine:
            'สถานที่ใช้ไฟฟ้า (Premise): 12 หมู่ 5 ต.สมมติ อ.ทดสอบ จ.ตัวอย่าง',
        accountHeader: const [
          'บัญชีแสดงสัญญา (CA)',
          'รหัสเครื่องวัด (Installation)',
          'เลขที่ใบแจ้ง (Invoice No.)',
          'ประเภท (Type)',
        ],
        accountRow: const ['1234567890', '0098765', 'MOCK-000001', '1.2'],
        meterHeader: const [
          'เลขอ่านครั้งหลัง (Last Meter Reading)',
          'เลขอ่านครั้งก่อน (Previous Meter Reading)',
          'จำนวนหน่วย (kWh)',
          'ตัวคูณ (Multiplier)',
        ],
        meterRows: const [
          ['4,120', '3,950', '170', '1'],
        ],
        costLines: const [
          ('ค่าพลังงานไฟฟ้า', '560.20'),
          ('ค่าบริการ', '38.22'),
          ('ค่า Ft (-0.1160 บาท/หน่วย)', '-19.72'),
          ('ส่วนลด', '0.00'),
          ('รวมค่าไฟฟ้าก่อนภาษีมูลค่าเพิ่ม', '578.70'),
          ('ภาษีมูลค่าเพิ่ม 7%', '40.51'),
        ],
        totalLabel: 'รวมค่าไฟฟ้าเดือนปัจจุบัน',
        totalValue: '619.21',
      );

  _BillMockData _meaTouData() => _BillMockData(
        logoLabel: 'MEA',
        providerName: 'การไฟฟ้านครหลวง (มอคอัพ)',
        providerSubtitle: 'ใบแจ้งค่าไฟฟ้า TOU · อัตรา TOU3',
        providerAbbr: 'MEA',
        customerNameLine: 'ชื่อผู้ใช้ไฟฟ้า (Name): นายตัวอย่าง เมืองดี',
        premiseLine:
            'สถานที่ใช้ไฟฟ้า (Premise): 88/8 ซอยสมมติ แขวงทดสอบ เขตตัวอย่าง กรุงเทพฯ',
        accountHeader: const [
          'บัญชีแสดงสัญญา (CA)',
          'รหัสเครื่องวัด (Installation)',
          'เลขที่ใบแจ้ง (Invoice No.)',
          'ประเภท (Type)',
        ],
        accountRow: const ['1122334455', 'ME00790', 'MOCK-TOU-000002', '1.2'],
        meterHeader: const [
          'ช่วงเวลา',
          'เลขอ่านครั้งหลัง (Last Meter Reading)',
          'เลขอ่านครั้งก่อน (Previous Meter Reading)',
          'หน่วย (kWh)',
          'ตัวคูณ (Multiplier)',
        ],
        meterRows: const [
          ['On-Peak', '2,140', '2,080', '60', '1'],
          ['Off-Peak', '3,610', '3,480', '130', '1'],
        ],
        footnote: 'On-Peak: จ.-ศ. 09.00-22.00 น. · Off-Peak: ช่วงเวลาอื่นและวันหยุดนักขัตฤกษ์',
        readingColIndex: 1,
        usedColIndex: 3,
        costLines: const [
          ('ค่าพลังงาน On-Peak (60 × 5.7982)', '347.89'),
          ('ค่าพลังงาน Off-Peak (130 × 2.6369)', '342.80'),
          ('ค่าบริการ', '38.22'),
          ('ค่าไฟฟ้าผันแปร (Ft) -0.1160 บาท/หน่วย', '-22.04'),
          ('ส่วนลด', '0.00'),
          ('รวมค่าไฟฟ้าก่อนภาษีมูลค่าเพิ่ม', '706.87'),
          ('ภาษีมูลค่าเพิ่ม 7%', '49.48'),
        ],
        totalLabel: 'รวมค่าไฟฟ้าเดือนปัจจุบัน',
        totalValue: '756.35',
      );

  _BillMockData _peaTouData() => _BillMockData(
        logoLabel: 'PEA',
        providerName: 'การไฟฟ้าส่วนภูมิภาค (มอคอัพ)',
        providerSubtitle: 'ใบแจ้งค่าไฟฟ้า TOU · อัตรา TOU3',
        providerAbbr: 'PEA',
        customerNameLine: 'ชื่อผู้ใช้ไฟฟ้า (Name): นายตัวอย่าง เมืองดี',
        premiseLine:
            'สถานที่ใช้ไฟฟ้า (Premise): 12 หมู่ 5 ต.สมมติ อ.ทดสอบ จ.ตัวอย่าง',
        accountHeader: const [
          'บัญชีแสดงสัญญา (CA)',
          'รหัสเครื่องวัด (Installation)',
          'เลขที่ใบแจ้ง (Invoice No.)',
          'ประเภท (Type)',
        ],
        accountRow: const ['1234567890', '0098766', 'MOCK-TOU-000003', '1.2'],
        meterHeader: const [
          'ช่วงเวลา',
          'เลขอ่านครั้งหลัง (Last Meter Reading)',
          'เลขอ่านครั้งก่อน (Previous Meter Reading)',
          'หน่วย (kWh)',
          'ตัวคูณ (Multiplier)',
        ],
        meterRows: const [
          ['On-Peak', '1,860', '1,795', '65', '1'],
          ['Off-Peak', '2,910', '2,760', '150', '1'],
        ],
        footnote: 'On-Peak: จ.-ศ. 09.00-22.00 น. · Off-Peak: ช่วงเวลาอื่นและวันหยุดนักขัตฤกษ์',
        readingColIndex: 1,
        usedColIndex: 3,
        costLines: const [
          ('ค่าพลังงาน On-Peak (65 × 5.7982)', '376.88'),
          ('ค่าพลังงาน Off-Peak (150 × 2.6369)', '395.54'),
          ('ค่าบริการ', '38.22'),
          ('ค่า Ft (-0.1160 บาท/หน่วย)', '-24.94'),
          ('ส่วนลด', '0.00'),
          ('รวมค่าไฟฟ้าก่อนภาษีมูลค่าเพิ่ม', '785.70'),
          ('ภาษีมูลค่าเพิ่ม 7%', '55.15'),
        ],
        totalLabel: 'รวมค่าไฟฟ้าเดือนปัจจุบัน',
        totalValue: '840.85',
      );

  // อ้างอิงคำศัพท์ตรงตามใบแจ้งค่าน้ำประปาจริงของ กปน. (การประปานครหลวง)
  // เพื่อให้ผู้ใช้เทียบตำแหน่ง/คำบนบิลจริงกับในแอปได้ตรงกัน ไม่ต้องเดา
  _BillMockData _mwaData() => _BillMockData(
        logoLabel: 'MWA',
        providerName: 'การประปานครหลวง (มอคอัพ)',
        providerSubtitle:
            'ใบแจ้งค่าน้ำประปา (Invoice) · MWA Call Center 1125',
        providerAbbr: 'กปน.',
        customerNameLine: 'ชื่อผู้ใช้น้ำ (Name): นายตัวอย่าง เมืองดี',
        premiseLine:
            'สถานที่ใช้น้ำ (Premise): 88/8 ซอยสมมติ แขวงทดสอบ เขตตัวอย่าง กรุงเทพฯ',
        typeLine: 'ประเภท (Type): 1.1',
        accountHeader: const [
          'ทะเบียนผู้ใช้น้ำ (Account no.)',
          'เลขที่แจ้งค่าน้ำ (Invoice no.)',
        ],
        accountRow: const ['2233445566', 'MOCK-000007'],
        meterHeader: const [
          'เลขในมาตร (Current reading)',
          'เลขในมาตร (Previous reading)',
          'จำนวนน้ำใช้ (Consumption)',
        ],
        meterRows: const [
          ['1,248', '1,230', '18'],
        ],
        costLines: const [
          ('ค่าน้ำประปา', '306.00'),
          ('ค่าบริการรายเดือน', '30.00'),
          ('ส่วนลด', '0.00'),
          ('ยอดเงินก่อนคิดภาษี', '336.00'),
          ('ภาษีมูลค่าเพิ่ม 7%', '23.52'),
        ],
        totalLabel: 'รวมเงินที่ต้องชำระทั้งสิ้น (Grand Total)',
        totalValue: '359.52',
      );

  _BillMockData _pwaData() => _BillMockData(
        logoLabel: 'PWA',
        providerName: 'การประปาส่วนภูมิภาค (มอคอัพ)',
        providerSubtitle:
            'ใบแจ้งค่าน้ำประปา (Invoice) · PWA Contact Center 1662',
        providerAbbr: 'กปภ.',
        customerNameLine: 'ชื่อผู้ใช้น้ำ (Name): นายตัวอย่าง เมืองดี',
        premiseLine:
            'สถานที่ใช้น้ำ (Premise): 12 หมู่ 5 ต.สมมติ อ.ทดสอบ จ.ตัวอย่าง',
        typeLine: 'ประเภท (Type): 1.1',
        accountHeader: const [
          'ทะเบียนผู้ใช้น้ำ (Account no.)',
          'เลขที่แจ้งค่าน้ำ (Invoice no.)',
        ],
        accountRow: const ['3344556677', 'MOCK-000009'],
        meterHeader: const [
          'เลขในมาตร (Current reading)',
          'เลขในมาตร (Previous reading)',
          'จำนวนน้ำใช้ (Consumption)',
        ],
        meterRows: const [
          ['876', '851', '25'],
        ],
        costLines: const [
          ('ค่าน้ำประปา', '425.00'),
          ('ค่าบริการรายเดือน', '40.00'),
          ('ค่ารักษามาตรวัดน้ำ', '10.00'),
          ('ส่วนลด', '0.00'),
          ('ยอดเงินก่อนคิดภาษี', '475.00'),
          ('ภาษีมูลค่าเพิ่ม 7%', '33.25'),
        ],
        totalLabel: 'รวมเงินที่ต้องชำระทั้งสิ้น (Grand Total)',
        totalValue: '508.25',
      );
}

class _BillMockData {
  final String logoLabel;
  final String providerName;
  final String providerSubtitle;
  final String providerAbbr;

  // บรรทัดชื่อผู้ใช้/สถานที่ใช้ — ข้อความเต็มพร้อม label ไทย/อังกฤษ แสดงเป็น
  // ข้อความธรรมดาเหนือกล่องบัญชี (ตามตำแหน่งบนบิลจริงที่ผู้ใช้ส่งมาเทียบ)
  final String customerNameLine;
  final String premiseLine;
  // เฉพาะน้ำ: บิลจริงมีช่อง "ประเภท (Type)" อยู่ในบล็อกชื่อผู้ใช้/สถานที่
  // ส่วนไฟฟ้า "ประเภท" อยู่ในตารางบัญชีแทน (ดู accountHeader) จึงไม่ต้องซ้ำ
  final String? typeLine;

  final List<String> accountHeader;
  final List<String> accountRow;
  final List<String> meterHeader;
  final List<List<String>> meterRows;
  final String? footnote;
  final List<(String, String)> costLines;
  final String totalLabel;
  final String totalValue;

  // ดัชนีคอลัมน์ใน meterRows/meterHeader ของช่อง "เลขอ่านครั้งหลัง" (ล้อม
  // กรอบแดงเสมอ) และช่อง "จำนวนหน่วย/จำนวนน้ำใช้" (ล้อมเพิ่มตอน highlightUsed)
  final int readingColIndex;
  final int usedColIndex;

  _BillMockData({
    required this.logoLabel,
    required this.providerName,
    required this.providerSubtitle,
    required this.providerAbbr,
    required this.customerNameLine,
    required this.premiseLine,
    this.typeLine,
    required this.accountHeader,
    required this.accountRow,
    required this.meterHeader,
    required this.meterRows,
    this.footnote,
    required this.costLines,
    required this.totalLabel,
    required this.totalValue,
    this.readingColIndex = 0,
    this.usedColIndex = 2,
  });
}