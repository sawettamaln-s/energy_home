// migrate_tou_bills.dart
//
// เครื่องมือ migration แบบใช้ครั้งเดียว (ไม่ใช่ฟีเจอร์ถาวร) — พอร์ตมาจาก
// FirestoreService.migrateTouCompiledBills() ใน lib/services/firestore_service.dart
// ให้รันเป็นสคริปต์ Dart standalone ได้ตรงๆ โดยไม่ต้องเปิดแอป Flutter
//
// ทำไมต้องพอร์ตแทนเรียกโค้ดเดิมตรงๆ:
//   ฟังก์ชันเดิมอยู่ใน FirestoreService ซึ่ง import 'package:cloud_firestore'
//   และ 'package:flutter/material.dart' — ทั้งคู่ผูกกับ Flutter engine
//   (platform channels) เรียกจาก `dart run` ตรงๆ ไม่ได้ สคริปต์นี้เลยคุยกับ
//   Firebase ผ่าน REST API แทน (Identity Toolkit สำหรับ sign-in + Firestore
//   REST สำหรับอ่าน/เขียนเอกสาร) โดยใช้แค่ dart:io / dart:convert ที่มากับ
//   Dart SDK เท่านั้น — ไม่ต้อง `dart pub get` เพิ่ม แพ็กเกจอะไรเลย
//
// ตรรกะการคำนวณ (เดินฐานมิเตอร์สะสมทีละรอบ, เงื่อนไขข้าม, การกันของเดิม
// ไม่ให้เขียนทับโดยไม่ตั้งใจ) เหมือนต้นฉบับทุกจุด — อ่านคอมเมนต์ในไฟล์เดิม
// ประกอบด้วยถ้าจะแก้ตรรกะ
//
// วิธีใช้:
//   1) หา Firebase Web API Key ของโปรเจกต์ (Firebase Console > Project
//      settings > General > Web API Key) และ Project ID
//   2) รัน dry-run ก่อนเสมอ (ค่าเริ่มต้นของสคริปต์คือ dry-run อยู่แล้ว):
//
//        dart run tool/migrate_tou_bills.dart \
//          --project-id=YOUR_PROJECT_ID \
//          --api-key=YOUR_FIREBASE_WEB_API_KEY \
//          --email=user@example.com
//
//      (ถ้าไม่ใส่ --password จะถามแบบซ่อนตัวอักษรตอนรัน)
//      อ่านตารางสรุปที่พิมพ์ออกมาให้ครบก่อนไปขั้นต่อไป
//
//   3) พอใจกับ preview แล้วค่อยรันซ้ำแบบ apply จริง (ต้องพิมพ์ยืนยันตอนรัน
//      หรือใส่ --yes ถ้ารันแบบ non-interactive เช่นใน CI):
//
//        dart run tool/migrate_tou_bills.dart \
//          --project-id=YOUR_PROJECT_ID \
//          --api-key=YOUR_FIREBASE_WEB_API_KEY \
//          --email=user@example.com \
//          --apply
//
//   หมายเหตุ: security rules ส่วนใหญ่จะผูก uid ของบิลกับ request.auth.uid
//   ของผู้ที่ sign-in อยู่ ดังนั้นต้อง sign-in ด้วยบัญชีของ user ที่จะ
//   migrate บิลให้เอง (หรือใส่ --uid ถ้า sign-in ด้วยบัญชี admin ที่ rules
//   อนุญาตให้เขียนบัญชีอื่นได้ — ถ้า rules ไม่อนุญาต จะเจอ PERMISSION_DENIED)
//
//   งานเสร็จแล้วลบไฟล์นี้ทิ้งได้เลย เป็นเครื่องมือใช้ครั้งเดียว

import 'dart:convert';
import 'dart:io';

const _identityToolkitUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';

void main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) return; // _parseArgs พิมพ์ help/error ให้แล้ว

  stdout.writeln(
      '=== TOU bill migration tool (${options.apply ? "APPLY" : "DRY-RUN"} mode) ===');

  final client = HttpClient();
  try {
    // ---------- 1) Sign in ----------
    stdout.writeln('\nกำลัง sign-in ด้วย ${options.email} ...');
    final auth = await _signIn(
      client: client,
      apiKey: options.apiKey,
      email: options.email,
      password: options.password,
    );
    final idToken = auth['idToken'] as String;
    final signedInUid = auth['localId'] as String;
    final targetUid = options.uid ?? signedInUid;
    stdout.writeln('sign-in สำเร็จ (signed-in uid: $signedInUid)');
    if (targetUid != signedInUid) {
      stdout.writeln(
          'หมายเหตุ: กำลัง migrate ให้ uid อื่น ($targetUid) ต่างจากบัญชีที่ sign-in — '
          'ถ้า security rules ไม่อนุญาต จะเจอ PERMISSION_DENIED ตอนอ่าน/เขียน');
    }

    final firestore = _FirestoreRestClient(
      client: client,
      projectId: options.projectId,
      idToken: idToken,
    );

    // ---------- 2) โหลด user + ตรวจว่าเป็น TOU ----------
    final userDoc = await firestore.getDocument('users/$targetUid');
    if (userDoc == null) {
      stderr.writeln('⏭️ ไม่พบ user document (uid=$targetUid) — ยกเลิก');
      exitCode = 1;
      return;
    }
    final userData = _decodeFields(userDoc['fields'] as Map<String, dynamic>);
    final meterType = (userData['meterType'] as String?) ?? 'normal';
    if (meterType != 'tou') {
      stdout.writeln(
          '⏭️ ข้าม migration: ไม่ใช่ user TOU (meterType=$meterType, uid=$targetUid)');
      return;
    }
    final billingDay = (userData['billingDay'] as num?)?.toInt() ?? 30;

    // ---------- 3) โหลดบิลที่ compiled ทั้งหมด เรียงเก่า -> ใหม่ ----------
    final billDocs = await firestore.listDocuments('users/$targetUid/bills');
    final bills = billDocs.map((doc) {
      final fields = _decodeFields(doc['fields'] as Map<String, dynamic>);
      fields['id'] = _docIdFromName(doc['name'] as String);
      return fields;
    }).where((b) => (b['source'] as String?) == 'compiled').toList()
      ..sort((a, b) {
        final aKey = (a['year'] as num).toInt() * 12 + (a['month'] as num).toInt();
        final bKey = (b['year'] as num).toInt() * 12 + (b['month'] as num).toInt();
        return aKey.compareTo(bKey);
      });

    if (bills.isEmpty) {
      stdout.writeln('ไม่มีบิล source=compiled ให้ migrate (uid=$targetUid)');
      return;
    }

    // ---------- 4) โหลด electricity_logs ทั้งหมด เรียงเก่า -> ใหม่ ----------
    final logDocs =
        await firestore.listDocuments('users/$targetUid/electricity_logs');
    final allLogs = logDocs.map((doc) {
      final fields = _decodeFields(doc['fields'] as Map<String, dynamic>);
      return {
        'date': DateTime.parse(fields['date'] as String),
        'peakMeterValue': (fields['peakMeterValue'] as num?)?.toDouble(),
        'offPeakMeterValue': (fields['offPeakMeterValue'] as num?)?.toDouble(),
      };
    }).toList()
      ..sort((a, b) =>
          (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    // ---------- 5) หาฐานตั้งต้นจาก start_meter_history ที่เก่าแก่สุด ----------
    final historyDocs = await firestore
        .listDocuments('users/$targetUid/start_meter_history');
    final history = historyDocs.map((doc) {
      final fields = _decodeFields(doc['fields'] as Map<String, dynamic>);
      return {
        'recordedAt': fields['recordedAt'] != null
            ? DateTime.parse(fields['recordedAt'] as String)
            : DateTime.now(),
        'peakValue': (fields['peakValue'] as num?)?.toDouble() ?? 0.0,
        'offPeakValue': (fields['offPeakValue'] as num?)?.toDouble() ?? 0.0,
      };
    }).toList();

    Map<String, dynamic>? earliestRecord;
    for (final r in history) {
      if (earliestRecord == null ||
          (r['recordedAt'] as DateTime)
              .isBefore(earliestRecord['recordedAt'] as DateTime)) {
        earliestRecord = r;
      }
    }

    double? basePeak = earliestRecord?['peakValue'] as double?;
    double? baseOffPeak = earliestRecord?['offPeakValue'] as double?;

    // ---------- 6) ไล่คำนวณทีละรอบ ----------
    final results = <_BillPreview>[];

    for (final bill in bills) {
      final year = (bill['year'] as num).toInt();
      final month = (bill['month'] as num).toInt();
      final endDate = _safeBillingDate(year, month, billingDay);
      final startDate = _getPreviousCycleStart(endDate, billingDay);

      final logsInCycle = allLogs
          .where((l) =>
              !(l['date'] as DateTime).isBefore(startDate) &&
              (l['date'] as DateTime).isBefore(endDate))
          .toList();

      final oldPeakUsed = (bill['electricityPeakUsed'] as num?)?.toDouble() ?? 0.0;
      final oldOffPeakUsed =
          (bill['electricityOffPeakUsed'] as num?)?.toDouble() ?? 0.0;

      if (logsInCycle.isEmpty || basePeak == null || baseOffPeak == null) {
        results.add(_BillPreview(
          billId: bill['id'] as String,
          year: year,
          month: month,
          oldPeakUsed: oldPeakUsed,
          newPeakUsed: oldPeakUsed,
          oldOffPeakUsed: oldOffPeakUsed,
          newOffPeakUsed: oldOffPeakUsed,
          skippedReason: logsInCycle.isEmpty
              ? 'ไม่มี log ไฟฟ้าเหลืออยู่ในช่วงรอบนี้ '
                  '(${_fmtDate(startDate)} - ${_fmtDate(endDate)})'
              : 'ไม่มี start_meter_history ให้ใช้เป็นฐานตั้งต้น (รอบแรกสุด)',
        ));
        if (logsInCycle.isNotEmpty) {
          final closing = logsInCycle.last;
          basePeak = (closing['peakMeterValue'] as double?) ?? basePeak;
          baseOffPeak = (closing['offPeakMeterValue'] as double?) ?? baseOffPeak;
        }
        continue;
      }

      final closingLog = logsInCycle.last;
      final closingPeak = (closingLog['peakMeterValue'] as double?) ?? basePeak;
      final closingOffPeak =
          (closingLog['offPeakMeterValue'] as double?) ?? baseOffPeak;

      final newPeakUsed = _calculateUsed(closingPeak, basePeak);
      final newOffPeakUsed = _calculateUsed(closingOffPeak, baseOffPeak);

      results.add(_BillPreview(
        billId: bill['id'] as String,
        year: year,
        month: month,
        oldPeakUsed: oldPeakUsed,
        newPeakUsed: newPeakUsed,
        oldOffPeakUsed: oldOffPeakUsed,
        newOffPeakUsed: newOffPeakUsed,
        matchedLogDate: closingLog['date'] as DateTime,
      ));

      basePeak = closingPeak;
      baseOffPeak = closingOffPeak;
    }

    // ---------- 7) พิมพ์ตารางสรุป ----------
    _printSummary(results);

    final toApply = results.where((r) => r.willChange).toList();
    if (toApply.isEmpty) {
      stdout.writeln('\nไม่มีบิลไหนต้องแก้ — ไม่ต้อง apply');
      return;
    }

    if (!options.apply) {
      stdout.writeln(
          '\n(นี่คือ dry-run เฉยๆ ยังไม่มีการเขียนข้อมูลใดๆ — รันซ้ำพร้อม --apply เมื่อพร้อม)');
      return;
    }

    // ---------- 8) ยืนยันก่อน apply จริง ----------
    if (!options.skipConfirm) {
      stdout.write(
          '\nกำลังจะเขียนทับ ${toApply.length} บิลจริงใน Firestore — พิมพ์ "yes" เพื่อยืนยัน: ');
      final answer = stdin.readLineSync()?.trim().toLowerCase();
      if (answer != 'yes') {
        stdout.writeln('ยกเลิก ไม่มีการเขียนข้อมูลใดๆ');
        return;
      }
    }

    stdout.writeln('\nกำลัง apply ...');
    var success = 0;
    var failed = 0;
    for (final r in toApply) {
      try {
        await firestore.patchDocumentFields(
          'users/$targetUid/bills/${r.billId}',
          {
            'electricityPeakUsed': r.newPeakUsed,
            'electricityOffPeakUsed': r.newOffPeakUsed,
          },
        );
        success++;
        stdout.writeln('  ✅ ${r.year}-${r.month.toString().padLeft(2, '0')} '
            '(${r.billId}) อัปเดตแล้ว');
      } catch (e) {
        failed++;
        stderr.writeln('  ❌ ${r.year}-${r.month.toString().padLeft(2, '0')} '
            '(${r.billId}) ล้มเหลว: $e');
      }
    }
    stdout.writeln('\nเสร็จสิ้น: สำเร็จ $success รายการ, ล้มเหลว $failed รายการ');
  } finally {
    client.close(force: true);
  }
}

// ==================== ตรรกะที่พอร์ตมาจากแอป (ต้องตรงกับต้นฉบับเป๊ะ) ====================

// ต้องเหมือน EnergyForecaster._safeBillingDate เป๊ะ เพื่อ reconstruct ขอบเขต
// รอบเก่าให้ตรงกับที่แอปใช้จริงตอน compileBill()
DateTime _safeBillingDate(int year, int month, int billingDay) {
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final safeDay = billingDay > lastDayOfMonth ? lastDayOfMonth : billingDay;
  return DateTime(year, month, safeDay);
}

// ต้องเหมือน EnergyForecaster.getPreviousCycleStart เป๊ะ
DateTime _getPreviousCycleStart(DateTime cycleStart, int billingDay) {
  final prevMonth = DateTime(cycleStart.year, cycleStart.month - 1, 1);
  return _safeBillingDate(prevMonth.year, prevMonth.month, billingDay);
}

// ต้องเหมือน EnergyCalculator.calculateUsed เป๊ะ
double _calculateUsed(double current, double previous) {
  if (current <= previous) return 0;
  return double.parse((current - previous).toStringAsFixed(2));
}

String _fmtDate(DateTime d) => d.toIso8601String().split('T').first;

// ==================== Preview model + การพิมพ์ตาราง ====================

class _BillPreview {
  final String billId;
  final int year;
  final int month;
  final double oldPeakUsed;
  final double newPeakUsed;
  final double oldOffPeakUsed;
  final double newOffPeakUsed;
  final DateTime? matchedLogDate;
  final String? skippedReason;

  _BillPreview({
    required this.billId,
    required this.year,
    required this.month,
    required this.oldPeakUsed,
    required this.newPeakUsed,
    required this.oldOffPeakUsed,
    required this.newOffPeakUsed,
    this.matchedLogDate,
    this.skippedReason,
  });

  bool get willChange =>
      skippedReason == null &&
      (oldPeakUsed != newPeakUsed || oldOffPeakUsed != newOffPeakUsed);
}

void _printSummary(List<_BillPreview> results) {
  stdout.writeln('\n--- สรุป preview (${results.length} บิล) ---');
  for (final r in results) {
    final label = '${r.year}-${r.month.toString().padLeft(2, '0')}';
    if (r.skippedReason != null) {
      stdout.writeln('  ⏭️  $label  ข้าม: ${r.skippedReason}');
    } else if (r.willChange) {
      stdout.writeln('  🔄 $label  '
          'peak: ${r.oldPeakUsed} -> ${r.newPeakUsed}, '
          'off-peak: ${r.oldOffPeakUsed} -> ${r.newOffPeakUsed}');
    } else {
      stdout.writeln('  ✔️  $label  ไม่มีอะไรเปลี่ยน '
          '(peak: ${r.oldPeakUsed}, off-peak: ${r.oldOffPeakUsed})');
    }
  }
  final willChange = results.where((r) => r.willChange).length;
  final skipped = results.where((r) => r.skippedReason != null).length;
  final unchanged = results.length - willChange - skipped;
  stdout.writeln(
      '\nรวม: จะเปลี่ยน $willChange | ไม่เปลี่ยน $unchanged | ข้าม $skipped');
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

// ==================== Firestore REST client ====================

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

  Future<Map<String, dynamic>?> getDocument(String relativePath) async {
    final uri = Uri.parse('$_baseUrl/$relativePath');
    final request = await client.getUrl(uri);
    request.headers.set('Authorization', 'Bearer $idToken');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception(
          'อ่าน $relativePath ล้มเหลว (${response.statusCode}): $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  // ดึงเอกสารทั้งหมดใน collection แบบไล่ทีละหน้า (pagination) — ไม่ orderBy
  // ในระดับ REST เพราะทุกจุดที่เรียกใช้ในสคริปต์นี้ sort เองอยู่แล้วในโค้ด
  // Dart (เหมือนที่ getBills/getStartMeterHistory ของแอปเดิมทำ)
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

  // อัปเดตเฉพาะฟิลด์ที่ระบุ (updateMask) — ปลอดภัยกว่าการ set() ทับทั้ง
  // เอกสารแบบต้นฉบับ เพราะไม่มีความเสี่ยงเผลอเขียนทับฟิลด์อื่นถ้าโครงสร้าง
  // ข้อมูลที่ fetch มาไม่ครบ ผลลัพธ์สุดท้ายเหมือนกันทุกประการกับต้นฉบับ
  // (เปลี่ยนแค่ electricityPeakUsed / electricityOffPeakUsed)
  Future<void> patchDocumentFields(
      String relativePath, Map<String, dynamic> fieldsToUpdate) async {
    final maskParams = fieldsToUpdate.keys
        .map((k) => 'updateMask.fieldPaths=$k')
        .join('&');
    final uri =
        Uri.parse('$_baseUrl/$relativePath?$maskParams');
    final request = await client.patchUrl(uri);
    request.headers.set('Authorization', 'Bearer $idToken');
    request.headers.set('Content-Type', 'application/json');
    request.write(jsonEncode({'fields': _encodeFields(fieldsToUpdate)}));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception('เขียน $relativePath ล้มเหลว (${response.statusCode}): $body');
    }
  }
}

String _docIdFromName(String name) => name.split('/').last;

// ==================== Firestore field <-> ค่า Dart ====================

Map<String, dynamic> _encodeFields(Map<String, dynamic> data) {
  final result = <String, dynamic>{};
  for (final entry in data.entries) {
    result[entry.key] = _encodeValue(entry.value);
  }
  return result;
}

Map<String, dynamic> _encodeValue(dynamic value) {
  if (value == null) return {'nullValue': null};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': value.toString()};
  if (value is double) return {'doubleValue': value};
  if (value is String) return {'stringValue': value};
  if (value is DateTime) return {'stringValue': value.toIso8601String()};
  throw Exception('ไม่รู้จักชนิดข้อมูล: ${value.runtimeType}');
}

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
  return null;
}

// ==================== CLI args ====================

class _Options {
  final String projectId;
  final String apiKey;
  final String email;
  final String password;
  final String? uid;
  final bool apply;
  final bool skipConfirm;

  _Options({
    required this.projectId,
    required this.apiKey,
    required this.email,
    required this.password,
    required this.uid,
    required this.apply,
    required this.skipConfirm,
  });
}

_Options? _parseArgs(List<String> args) {
  String? projectId;
  String? apiKey;
  String? email;
  String? password;
  String? uid;
  var apply = false;
  var skipConfirm = false;

  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      _printHelp();
      return null;
    } else if (arg == '--apply') {
      apply = true;
    } else if (arg == '--yes') {
      skipConfirm = true;
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
    } catch (_) {
      // stdin ไม่ใช่ terminal แบบ interactive (เช่นรันใน CI/pipe) — พิมพ์
      // แบบไม่ซ่อนตัวอักษรแทน ดีกว่า throw แล้วสคริปต์ใช้งานไม่ได้เลย
    }
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
    apply: apply,
    skipConfirm: skipConfirm,
  );
}

void _printHelp() {
  stdout.writeln('''
วิธีใช้:
  dart run tool/migrate_tou_bills.dart --project-id=ID --api-key=KEY --email=EMAIL [options]

Required:
  --project-id=ID      Firebase project ID
  --api-key=KEY        Firebase Web API Key (Project settings > General)
  --email=EMAIL        อีเมลของ user ที่จะ migrate บิลให้

Optional:
  --password=PASSWORD  ถ้าไม่ใส่จะถามแบบซ่อนตัวอักษรตอนรัน
  --uid=UID             migrate ให้ uid อื่นที่ไม่ใช่บัญชีที่ sign-in (ต้องมีสิทธิ์ตาม security rules)
  --apply               apply จริง (ไม่ใส่ = dry-run preview อย่างเดียว, ไม่เขียนอะไร)
  --yes                 ข้ามขั้นตอนยืนยันตอน apply (ใช้ตอนรันแบบ non-interactive)
  --help                แสดงข้อความนี้
''');
}