// list_bills.dart
//
// เครื่องมือ read-only (ไม่เขียนอะไรลง Firestore เลย) ไว้ดูภาพรวมบิลทั้งหมด
// ของ user คนหนึ่ง จัดกลุ่มตามปี-เดือน แล้วชี้ให้เห็นว่าเดือนไหนมีบิลซ้อน
// กันมากกว่า 1 ใบบ้าง — เขียนไว้ช่วยตรวจสอบก่อนตัดสินใจลบข้อมูลอะไรใน
// Firestore Console เอง สคริปต์นี้ใช้ครั้งเดียวก็ลบทิ้งได้เหมือนกัน
//
// วิธีใช้ (เหมือน migrate_tou_bills.dart ทุกอย่าง):
//   dart run tool/list_bills.dart \
//     --project-id=YOUR_PROJECT_ID \
//     --api-key=YOUR_FIREBASE_WEB_API_KEY \
//     --email=user@example.com

import 'dart:convert';
import 'dart:io';

const _identityToolkitUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';

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

    final billDocs = await firestore.listDocuments('users/$targetUid/bills');
    final bills = billDocs.map((doc) {
      final fields = _decodeFields(doc['fields'] as Map<String, dynamic>);
      fields['id'] = _docIdFromName(doc['name'] as String);
      return fields;
    }).toList();

    if (bills.isEmpty) {
      stdout.writeln('ไม่มีบิลเลยสำหรับ uid นี้');
      return;
    }

    // จัดกลุ่มตาม (year, month)
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final b in bills) {
      final year = (b['year'] as num?)?.toInt() ?? 0;
      final month = (b['month'] as num?)?.toInt() ?? 0;
      final key = '$year-${month.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(b);
    }

    final sortedKeys = groups.keys.toList()..sort();

    stdout.writeln('=== บิลทั้งหมด ${bills.length} ใบ, ${groups.length} รอบบิล ===\n');

    var duplicateGroups = 0;
    for (final key in sortedKeys) {
      final group = groups[key]!;
      final isDup = group.length > 1;
      if (isDup) duplicateGroups++;
      stdout.writeln('${isDup ? '⚠️ ' : '   '}$key — ${group.length} ใบ'
          '${isDup ? '  <<< ซ้อนกัน' : ''}');
      for (final b in group) {
        final source = b['source'] as String? ?? '(ไม่มี source)';
        final totalCost = b['totalCost'] as num? ?? 0;
        final peakUsed = b['electricityPeakUsed'] as num? ?? 0;
        final offPeakUsed = b['electricityOffPeakUsed'] as num? ?? 0;
        final elecUsed = b['electricityUsed'] as num? ?? 0;
        stdout.writeln('       - id: ${b['id']}');
        stdout.writeln('         source: $source, totalCost: $totalCost, '
            'electricityUsed: $elecUsed, peakUsed: $peakUsed, offPeakUsed: $offPeakUsed');
      }
      stdout.writeln('');
    }

    stdout.writeln('--- สรุป: $duplicateGroups รอบที่มีบิลซ้อนกัน จาก ${groups.length} รอบทั้งหมด ---');
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

String _docIdFromName(String name) => name.split('/').last;

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
  dart run tool/list_bills.dart --project-id=ID --api-key=KEY --email=EMAIL [options]

Required:
  --project-id=ID      Firebase project ID
  --api-key=KEY        Firebase Web API Key
  --email=EMAIL        อีเมลของ user ที่จะดูรายการบิล

Optional:
  --password=PASSWORD  ถ้าไม่ใส่จะถามแบบซ่อนตัวอักษรตอนรัน
  --uid=UID             ดูบิลของ uid อื่นที่ไม่ใช่บัญชีที่ sign-in
  --help                แสดงข้อความนี้
''');
}