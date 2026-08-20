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
/// — เจตนาให้เห็นแค่ "ตำแหน่ง" ของแต่ละค่าบนบิล ไม่ใช่คำนวณยอดจริง
class BillMockupCard extends StatelessWidget {
  final bool isElectricity;
  final String area; // 'bangkok' หรือ 'province'
  final bool isTou; // ใช้เฉพาะฝั่งไฟฟ้า

  const BillMockupCard({
    super.key,
    required this.isElectricity,
    required this.area,
    this.isTou = false,
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
          _infoTable(data.accountRows),
          const SizedBox(height: 8),
          _infoTable(data.meterRows, headerRow: data.meterHeader),
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

  Widget _infoTable(List<List<String>> rows, {List<String>? headerRow}) {
    final allRows = [if (headerRow != null) headerRow, ...rows];
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
              for (final cell in allRows[r])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    cell,
                    style: TextStyle(
                      fontSize: r == 0 && headerRow != null ? 9.5 : 11,
                      color: r == 0 && headerRow != null
                          ? Colors.grey.shade500
                          : DashboardStyles.textDark,
                    ),
                  ),
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
        accountRows: [
          ['CA: 1122334455', 'รหัสเครื่องวัด: ME00789', 'เลขที่ใบแจ้ง: MOCK-000004'],
        ],
        meterHeader: ['เลขอ่านครั้งหลัง', 'เลขอ่านครั้งก่อน', 'จำนวนหน่วย'],
        meterRows: [
          ['3,593', '3,493', '100'],
        ],
        costLines: const [
          ('ค่าพลังงานไฟฟ้า', '324.80'),
          ('ค่าบริการ', '38.22'),
          ('ค่าไฟฟ้าผันแปร (Ft) -0.1160 บาท/หน่วย', '-11.60'),
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
        accountRows: [
          ['CA: 1234567890', 'รหัสเครื่องวัด: 0098765', 'เลขที่ใบแจ้ง: MOCK-000001'],
        ],
        meterHeader: ['เลขอ่านครั้งหลัง', 'เลขอ่านครั้งก่อน', 'จำนวนหน่วย'],
        meterRows: [
          ['4,120', '3,950', '170'],
        ],
        costLines: const [
          ('ค่าพลังงานไฟฟ้า', '560.20'),
          ('ค่าบริการ', '38.22'),
          ('ค่า Ft (-0.1160 บาท/หน่วย)', '-19.72'),
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
        accountRows: [
          ['CA: 1122334455', 'เลขที่ใบแจ้ง: MOCK-TOU-000002'],
        ],
        meterHeader: ['ช่วงเวลา', 'เลขอ่านครั้งหลัง', 'เลขอ่านครั้งก่อน', 'หน่วย'],
        meterRows: [
          ['On-Peak', '2,140', '2,080', '60'],
          ['Off-Peak', '3,610', '3,480', '130'],
        ],
        footnote: 'On-Peak: จ.-ศ. 09.00-22.00 น. · Off-Peak: ช่วงเวลาอื่นและวันหยุดนักขัตฤกษ์',
        costLines: const [
          ('ค่าพลังงาน On-Peak (60 × 5.7982)', '347.89'),
          ('ค่าพลังงาน Off-Peak (130 × 2.6369)', '342.80'),
          ('ค่าบริการ', '38.22'),
          ('ค่าไฟฟ้าผันแปร (Ft) -0.1160 บาท/หน่วย', '-22.04'),
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
        accountRows: [
          ['CA: 1234567890', 'เลขที่ใบแจ้ง: MOCK-TOU-000003'],
        ],
        meterHeader: ['ช่วงเวลา', 'เลขอ่านครั้งหลัง', 'เลขอ่านครั้งก่อน', 'หน่วย'],
        meterRows: [
          ['On-Peak', '1,860', '1,795', '65'],
          ['Off-Peak', '2,910', '2,760', '150'],
        ],
        footnote: 'On-Peak: จ.-ศ. 09.00-22.00 น. · Off-Peak: ช่วงเวลาอื่นและวันหยุดนักขัตฤกษ์',
        costLines: const [
          ('ค่าพลังงาน On-Peak (65 × 5.7982)', '376.88'),
          ('ค่าพลังงาน Off-Peak (150 × 2.6369)', '395.54'),
          ('ค่าบริการ', '38.22'),
          ('ค่า Ft (-0.1160 บาท/หน่วย)', '-24.94'),
          ('ภาษีมูลค่าเพิ่ม 7%', '55.15'),
        ],
        totalLabel: 'รวมค่าไฟฟ้าเดือนปัจจุบัน',
        totalValue: '840.85',
      );

  _BillMockData _mwaData() => _BillMockData(
        logoLabel: 'MWA',
        providerName: 'การประปานครหลวง (มอคอัพ)',
        providerSubtitle: 'ใบแจ้งค่าน้ำประปา · MWA Call Center 1125',
        providerAbbr: 'กปน.',
        accountRows: [
          ['เลขที่ผู้ใช้น้ำ: 2233445566', 'เลขที่มาตรวัดน้ำ: MW01122', 'เลขที่ใบแจ้ง: MOCK-000007'],
        ],
        meterHeader: ['เลขอ่านครั้งนี้', 'เลขอ่านครั้งก่อน', 'จำนวนหน่วย (ลบ.ม.)'],
        meterRows: [
          ['1,248', '1,230', '18'],
        ],
        costLines: const [
          ('ค่าน้ำประปา', '306.00'),
          ('ค่าบริการรายเดือน', '30.00'),
          ('ภาษีมูลค่าเพิ่ม 7%', '23.52'),
        ],
        totalLabel: 'รวมค่าน้ำประปาเดือนปัจจุบัน',
        totalValue: '359.52',
      );

  _BillMockData _pwaData() => _BillMockData(
        logoLabel: 'PWA',
        providerName: 'การประปาส่วนภูมิภาค (มอคอัพ)',
        providerSubtitle: 'ใบแจ้งค่าน้ำประปา · PWA Contact Center 1662',
        providerAbbr: 'กปภ.',
        accountRows: [
          ['เลขที่ผู้ใช้น้ำ: 3344556677', 'เลขที่มาตรวัดน้ำ: PW00543', 'เลขที่ใบแจ้ง: MOCK-000009'],
        ],
        meterHeader: ['เลขอ่านครั้งนี้', 'เลขอ่านครั้งก่อน', 'จำนวนหน่วย (ลบ.ม.)'],
        meterRows: [
          ['876', '851', '25'],
        ],
        costLines: const [
          ('ค่าน้ำประปา', '425.00'),
          ('ค่าบริการรายเดือน', '40.00'),
          ('ค่ารักษามาตรวัดน้ำ', '10.00'),
          ('ภาษีมูลค่าเพิ่ม 7%', '33.25'),
        ],
        totalLabel: 'รวมค่าน้ำประปาเดือนปัจจุบัน',
        totalValue: '508.25',
      );
}

class _BillMockData {
  final String logoLabel;
  final String providerName;
  final String providerSubtitle;
  final String providerAbbr;
  final List<List<String>> accountRows;
  final List<String> meterHeader;
  final List<List<String>> meterRows;
  final String? footnote;
  final List<(String, String)> costLines;
  final String totalLabel;
  final String totalValue;

  _BillMockData({
    required this.logoLabel,
    required this.providerName,
    required this.providerSubtitle,
    required this.providerAbbr,
    required this.accountRows,
    required this.meterHeader,
    required this.meterRows,
    this.footnote,
    required this.costLines,
    required this.totalLabel,
    required this.totalValue,
  });
}