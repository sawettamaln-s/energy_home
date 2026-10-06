// backtest_cycle_projection.dart
//
// วัดความแม่นยำของ "ยอดสิ้นรอบบิล" (การ์ดบิลรอบนี้ในหน้าวิเคราะห์ / แจ้งเตือน
// แนวโน้มสูงขึ้น / บิลที่ระบบปิดให้) ย้อนหลังกับข้อมูลจริงของบัญชีหนึ่ง
// read-only — ไม่เขียนอะไรลง Firestore
//
// ใช้รอบที่ปิดแล้วทุกรอบที่มีเลขต้นรอบของรอบถัดไป (หน่วยจริงจากใบแจ้งหนี้) และ
// มีบันทึกมิเตอร์ในรอบ แล้วแกล้งคาดการณ์ ณ วันที่ 3, 5, 7, 10, 15, 20, 25 ของรอบ
// ด้วยฟังก์ชันเดียวกับแอป (EnergyForecaster.projectToCycleEnd) เทียบกับหน่วยจริง
// รายละเอียดวิธีและการเลือกน้ำหนักบิลรอบก่อน (k) ดู tool/cycle_backtest/cycle_backtest.dart
//
// วิธีใช้:
//   dart run tool/backtest_cycle_projection.dart \
//     --project-id=YOUR_PROJECT_ID \
//     --api-key=YOUR_FIREBASE_WEB_API_KEY \
//     --email=user@example.com
//
// ผลลัพธ์: ตาราง MAPE ต่อวันของรอบ, ความเอนเอียง, MAE, k ที่แม่นที่สุด และผล
// leave-one-cycle-out cross-validation แยกไฟฟ้ากับน้ำ — นำไปอ้างอิงในเล่มได้

import 'dart:convert';
import 'dart:io';

import 'cycle_backtest/cycle_backtest.dart';

const _identityToolkitUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';

void main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) return;

  final client = HttpClient();
  try {
    stdout.writeln('กำลัง sign-in ด้วย ${options.email} ...');
    final auth = await _signIn(client, options.apiKey, options.email, options.password);
    final uid = options.uid ?? (auth['localId'] as String);
    final firestore = _FirestoreRestClient(client, options.projectId, auth['idToken'] as String);

    final user = await firestore.getDocument('users/$uid');
    if (user == null) {
      stderr.writeln('ไม่พบข้อมูลผู้ใช้ uid=$uid');
      exitCode = 1;
      return;
    }
    final billingDay = (user['billingDay'] as num?)?.toInt() ?? 30;
    final isTou = user['meterType'] == 'tou';
    stdout.writeln('uid: $uid · วันตัดรอบ: $billingDay · มิเตอร์: ${isTou ? 'TOU' : 'ปกติ'}\n');

    final records = await firestore.listDocuments('users/$uid/start_meter_history');
    double num0(Map<String, dynamic> m, String k) => (m[k] as num?)?.toDouble() ?? 0;
    List<StartReading> starts(double Function(Map<String, dynamic>) value) => [
          for (final r in records)
            if (value(r) > 0)
              (
                year: (r['billingYear'] as num).toInt(),
                month: (r['billingMonth'] as num).toInt(),
                value: value(r),
              ),
        ];
    List<Reading> readings(List<Map<String, dynamic>> logs) => [
          for (final l in logs)
            (at: DateTime.parse(l['date'] as String), usedFromStart: num0(l, 'usedFromStart')),
        ];

    final eCycles = buildCycles(
      starts: starts((r) => isTou ? num0(r, 'peakValue') + num0(r, 'offPeakValue') : num0(r, 'electricityValue')),
      readings: readings(await firestore.listDocuments('users/$uid/electricity_logs')),
      billingDay: billingDay,
    );
    final wCycles = buildCycles(
      starts: starts((r) => num0(r, 'waterValue')),
      readings: readings(await firestore.listDocuments('users/$uid/water_logs')),
      billingDay: billingDay,
    );

    stdout.write(report('ไฟฟ้า (หน่วย kWh)', eCycles));
    stdout.write(report('น้ำประปา (ลบ.ม.)', wCycles));
  } catch (e) {
    stderr.writeln('เกิดข้อผิดพลาด: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}

// ==================== Firebase REST (read-only) ====================

Future<Map<String, dynamic>> _signIn(
    HttpClient client, String apiKey, String email, String password) async {
  final request = await client.postUrl(Uri.parse('$_identityToolkitUrl?key=$apiKey'));
  request.headers.set('Content-Type', 'application/json');
  request.write(jsonEncode({'email': email, 'password': password, 'returnSecureToken': true}));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw Exception('sign-in ล้มเหลว (${response.statusCode}): $body');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

class _FirestoreRestClient {
  _FirestoreRestClient(this.client, this.projectId, this.idToken);

  final HttpClient client;
  final String projectId;
  final String idToken;

  String get _baseUrl =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  Future<Map<String, dynamic>?> getDocument(String path) async {
    final request = await client.getUrl(Uri.parse('$_baseUrl/$path'));
    request.headers.set('Authorization', 'Bearer $idToken');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('อ่าน $path ล้มเหลว (${response.statusCode}): $body');
    }
    final doc = jsonDecode(body) as Map<String, dynamic>;
    return _decodeFields((doc['fields'] as Map<String, dynamic>?) ?? {});
  }

  Future<List<Map<String, dynamic>>> listDocuments(String path) async {
    final docs = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final query = <String, String>{'pageSize': '300'};
      if (pageToken != null) query['pageToken'] = pageToken;
      final request = await client.getUrl(Uri.parse('$_baseUrl/$path').replace(queryParameters: query));
      request.headers.set('Authorization', 'Bearer $idToken');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception('อ่าน $path ล้มเหลว (${response.statusCode}): $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      for (final d in (decoded['documents'] as List?) ?? []) {
        docs.add(_decodeFields(((d as Map<String, dynamic>)['fields'] as Map<String, dynamic>?) ?? {}));
      }
      pageToken = decoded['nextPageToken'] as String?;
    } while (pageToken != null);
    return docs;
  }
}

Map<String, dynamic> _decodeFields(Map<String, dynamic> fields) =>
    {for (final e in fields.entries) e.key: _decodeValue(e.value as Map<String, dynamic>)};

dynamic _decodeValue(Map<String, dynamic> value) {
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('integerValue')) return int.parse(value['integerValue'] as String);
  if (value.containsKey('doubleValue')) return (value['doubleValue'] as num).toDouble();
  if (value.containsKey('booleanValue')) return value['booleanValue'];
  if (value.containsKey('timestampValue')) return value['timestampValue'];
  return null; // null, array, map — สคริปต์นี้ไม่ใช้
}

// ==================== CLI args ====================

typedef _Options = ({String projectId, String apiKey, String email, String password, String? uid});

_Options? _parseArgs(List<String> args) {
  String? projectId, apiKey, email, password, uid;
  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      _printHelp();
      return null;
    } else if (arg.startsWith('--project-id=')) {
      projectId = arg.substring('--project-id='.length);
    } else if (arg.startsWith('--api-key=')) {
      apiKey = arg.substring('--api-key='.length);
    } else if (arg.startsWith('--email=')) {
      email = arg.substring('--email='.length);
    } else if (arg.startsWith('--password=')) {
      password = arg.substring('--password='.length);
    } else if (arg.startsWith('--uid=')) {
      uid = arg.substring('--uid='.length);
    } else {
      stderr.writeln('ไม่รู้จัก argument: $arg');
      _printHelp();
      exitCode = 1;
      return null;
    }
  }
  if (projectId == null || apiKey == null || email == null) {
    stderr.writeln('ขาด argument ที่จำเป็น (--project-id, --api-key, --email)\n');
    _printHelp();
    exitCode = 1;
    return null;
  }
  if (password == null) {
    stdout.write('Password สำหรับ $email: ');
    try {
      stdin.echoMode = false;
    } catch (_) {}
    password = stdin.readLineSync() ?? '';
    try {
      stdin.echoMode = true;
    } catch (_) {}
    stdout.writeln();
  }
  return (projectId: projectId, apiKey: apiKey, email: email, password: password, uid: uid);
}

void _printHelp() {
  stdout.writeln('''
วิธีใช้:
  dart run tool/backtest_cycle_projection.dart --project-id=ID --api-key=KEY --email=EMAIL [options]

Required:
  --project-id=ID      Firebase project ID
  --api-key=KEY        Firebase Web API Key
  --email=EMAIL        อีเมลของบัญชีที่จะวัด

Optional:
  --password=PASSWORD  ถ้าไม่ใส่จะถามตอนรัน
  --uid=UID            วัดบัญชีอื่นที่ไม่ใช่บัญชีที่ sign-in
  --help               แสดงข้อความนี้
''');
}
