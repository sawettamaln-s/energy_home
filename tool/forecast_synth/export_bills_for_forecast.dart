// export_bills_for_forecast.dart
//
// Export ประวัติบิลจริงของ 1 บัญชี (uid เดียว) จาก Firestore ออกมาเป็น CSV
// schema เดียวกับข้อมูลสมมติใน tool/forecast_synth/case*.csv เพื่อเอาไปผสม
// (weighted average) กับ seasonal curve ที่ได้จาก synthetic data
//
// อ่านอย่างเดียว ไม่เขียนอะไรกลับ Firestore เลย (เหมือน list_bills.dart)
//
// ตรรกะแบ่งเคส: อ่าน field `area` ('bangkok'/'province') และ `meterType`
// ('normal'/'tou') จาก users/{uid} แล้วเลือกไฟล์ output ให้ตรงเคส:
//   bangkok  + normal -> real_bangkok_normal.csv
//   bangkok  + tou     -> real_bangkok_tou.csv
//   province + normal -> real_upcountry_normal.csv
//   province + tou     -> real_upcountry_tou.csv
//
// รันได้หลายครั้งสำหรับหลาย uid/account — ข้อมูลจะถูก "append" ต่อท้ายไฟล์
// เดิม ไม่เขียนทับ (เผื่อมีมากกว่า 1 บัญชีจริงที่จะเอามาใช้)
//
// วิธีใช้ (เหมือน list_bills.dart ทุกอย่าง):
//   dart run tool/forecast_synth/export_bills_for_forecast.dart \
//     --project-id=YOUR_PROJECT_ID \
//     --api-key=YOUR_FIREBASE_WEB_API_KEY \
//     --email=user@example.com

import 'dart:convert';
import 'dart:io';

const _identityToolkitUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';

const _outputDir = 'tool/forecast_synth';

void main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) return;

  final client = HttpClient();
  try {
    stdout.writeln('กำลัง sign-in ด้วย ${options.email} ...');
    final auth = await _signIn(
      client: client,
      apiKey: options.apiKey,
      email: options.email,
      password: options.password,
    );
    final idToken = auth['idToken'] as String;
    final targetUid = options.uid ?? (auth['localId'] as String);
    stdout.writeln('sign-in สำเร็จ (uid: $targetUid)\n');

    final firestore = _FirestoreRestClient(
      client: client,
      projectId: options.projectId,
      idToken: idToken,
    );

    // 1) อ่าน user doc เพื่อรู้ area/meterType ของบัญชีนี้
    final userDoc = await firestore.getDocument('users/$targetUid');
    if (userDoc == null) {
      stderr.writeln('ไม่พบ users/$targetUid — ตรวจสอบ uid อีกครั้ง');
      exitCode = 1;
      return;
    }
    final userFields = _decodeFields(userDoc['fields'] as Map<String, dynamic>);
    final area = (userFields['area'] as String?) ?? 'bangkok';
    final meterType = (userFields['meterType'] as String?) ?? 'normal';
    final isTou = meterType == 'tou';
    final caseName =
        '${area == 'bangkok' ? 'bangkok' : 'upcountry'}_${isTou ? 'tou' : 'normal'}';
    stdout.writeln('บัญชีนี้: area=$area, meterType=$meterType -> case=$caseName\n');

    // 2) อ่านบิลทั้งหมดของ uid นี้
    final billDocs = await firestore.listDocuments('users/$targetUid/bills');
    final bills = billDocs.map((doc) {
      return _decodeFields(doc['fields'] as Map<String, dynamic>);
    }).toList();

    if (bills.isEmpty) {
      stdout.writeln('ไม่มีบิลเลยสำหรับ uid นี้ — ไม่มีอะไรให้ export');
      return;
    }

    // เรียงตาม year/month ให้แน่ใจ (แม้ order จาก Firestore จะไม่รับประกัน)
    bills.sort((a, b) {
      final ya = (a['year'] as num?)?.toInt() ?? 0;
      final ma = (a['month'] as num?)?.toInt() ?? 0;
      final yb = (b['year'] as num?)?.toInt() ?? 0;
      final mb = (b['month'] as num?)?.toInt() ?? 0;
      return (ya * 100 + ma).compareTo(yb * 100 + mb);
    });

    // 3) เขียน/append CSV ตาม schema เดียวกับ synthetic
    final outDir = Directory(_outputDir);
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final outPath = '$_outputDir/real_$caseName.csv';
    final outFile = File(outPath);
    final isNewFile = !outFile.existsSync();

    final sink = outFile.openWrite(mode: FileMode.append);
    if (isNewFile) {
      if (isTou) {
        sink.writeln('household_id,case,year,month,'
            'elec_units_onpeak,elec_units_offpeak,water_units');
      } else {
        sink.writeln('household_id,case,year,month,elec_units,water_units');
      }
    }

    var rowCount = 0;
    var skipped = 0;
    for (final b in bills) {
      final year = (b['year'] as num?)?.toInt() ?? 0;
      final month = (b['month'] as num?)?.toInt() ?? 0;
      if (year == 0 || month == 0) {
        skipped++;
        continue;
      }
      final water = (b['waterUsed'] as num?)?.toDouble() ?? 0;

      if (isTou) {
        final onpeak = (b['electricityPeakUsed'] as num?)?.toDouble() ?? 0;
        final offpeak = (b['electricityOffPeakUsed'] as num?)?.toDouble() ?? 0;
        sink.writeln('$targetUid,$caseName,$year,$month,$onpeak,$offpeak,$water');
      } else {
        final elec = (b['electricityUsed'] as num?)?.toDouble() ?? 0;
        sink.writeln('$targetUid,$caseName,$year,$month,$elec,$water');
      }
      rowCount++;
    }
    await sink.flush();
    await sink.close();

    stdout.writeln('เขียน/append $rowCount แถวลง $outPath แล้ว'
        '${skipped > 0 ? ' (ข้าม $skipped แถวที่ไม่มี year/month)' : ''}');
  } finally {
    client.close(force: true);
  }
}

// ==================== Firebase Auth (Identity Toolkit) REST ====================

Future<Map<String, dynamic>> _signIn({
  required HttpClient client,
  required String apiKey,
  required String email,
  required String password,
}) async {
  final uri = Uri.parse('$_identityToolkitUrl?key=$apiKey');
  final request = await client.postUrl(uri);
  request.headers.set('Content-Type', 'application/json');
  request.write(jsonEncode({
    'email': email,
    'password': password,
    'returnSecureToken': true,
  }));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw Exception('sign-in ล้มเหลว (${response.statusCode}): $body');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

// ==================== Firestore REST client (read-only) ====================

class _FirestoreRestClient {
  _FirestoreRestClient({
    required this.client,
    required this.projectId,
    required this.idToken,
  });

  final HttpClient client;
  final String projectId;
  final String idToken;

  String get _baseUrl =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  Future<Map<String, dynamic>?> getDocument(String relativeDocPath) async {
    final uri = Uri.parse('$_baseUrl/$relativeDocPath');
    final request = await client.getUrl(uri);
    request.headers.set('Authorization', 'Bearer $idToken');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('อ่าน $relativeDocPath ล้มเหลว (${response.statusCode}): $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listDocuments(
      String relativeCollectionPath) async {
    final docs = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final query = <String, String>{'pageSize': '300'};
      if (pageToken != null) query['pageToken'] = pageToken;
      final uri = Uri.parse('$_baseUrl/$relativeCollectionPath')
          .replace(queryParameters: query);
      final request = await client.getUrl(uri);
      request.headers.set('Authorization', 'Bearer $idToken');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception(
            'อ่าน $relativeCollectionPath ล้มเหลว (${response.statusCode}): $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final pageDocs = (decoded['documents'] as List?) ?? [];
      docs.addAll(pageDocs.cast<Map<String, dynamic>>());
      pageToken = decoded['nextPageToken'] as String?;
    } while (pageToken != null);
    return docs;
  }
}

// ==================== Firestore field <-> ค่า Dart ====================

Map<String, dynamic> _decodeFields(Map<String, dynamic> fields) {
  final result = <String, dynamic>{};
  for (final entry in fields.entries) {
    result[entry.key] = _decodeValue(entry.value as Map<String, dynamic>);
  }
  return result;
}

dynamic _decodeValue(Map<String, dynamic> value) {
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('integerValue')) {
    return int.parse(value['integerValue'] as String);
  }
  if (value.containsKey('doubleValue')) {
    final v = value['doubleValue'];
    return v is int ? v.toDouble() : v as double;
  }
  if (value.containsKey('booleanValue')) return value['booleanValue'];
  if (value.containsKey('nullValue')) return null;
  if (value.containsKey('timestampValue')) return value['timestampValue'];
  throw Exception('ไม่รู้จักชนิดฟิลด์ Firestore: ${value.keys}');
}

// ==================== CLI args ====================

class _Options {
  final String projectId;
  final String apiKey;
  final String email;
  final String password;
  final String? uid;

  _Options({
    required this.projectId,
    required this.apiKey,
    required this.email,
    required this.password,
    required this.uid,
  });
}

_Options? _parseArgs(List<String> args) {
  String? projectId;
  String? apiKey;
  String? email;
  String? password;
  String? uid;

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
    var hideInput = false;
    try {
      stdin.echoMode = false;
      hideInput = true;
    } catch (_) {}
    password = stdin.readLineSync() ?? '';
    if (hideInput) stdin.echoMode = true;
    stdout.writeln();
  }

  return _Options(
    projectId: projectId,
    apiKey: apiKey,
    email: email,
    password: password,
    uid: uid,
  );
}

void _printHelp() {
  stdout.writeln('''
วิธีใช้:
  dart run tool/forecast_synth/export_bills_for_forecast.dart \\
    --project-id=ID --api-key=KEY --email=EMAIL [options]

Required:
  --project-id=ID      Firebase project ID
  --api-key=KEY        Firebase Web API Key
  --email=EMAIL        อีเมลของบัญชีที่จะ export บิล

Optional:
  --password=PASSWORD  ถ้าไม่ใส่จะถามแบบซ่อนตัวอักษรตอนรัน
  --uid=UID             export บิลของ uid อื่นที่ไม่ใช่บัญชีที่ sign-in
                        (ต้องมีสิทธิ์อ่านตาม Firestore security rules)
  --help                แสดงข้อความนี้

ผลลัพธ์: append แถวลง tool/forecast_synth/real_<case>.csv
  โดย <case> คำนวณจาก area+meterType ของบัญชีนั้น เช่น
  real_bangkok_normal.csv, real_bangkok_tou.csv,
  real_upcountry_normal.csv, real_upcountry_tou.csv
''');
}