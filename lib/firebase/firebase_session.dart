import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/manager.dart';
import '../storage/storage.dart' as storage;
import 'command_executor.dart';
import 'firebase_config.dart';
import 'public_snapshot.dart';

class FirebaseSession extends ChangeNotifier {
  FirebaseSession({
    required this.user,
    required this.role,
    FirebaseFirestore? firestore,
  }) : db = firestore ?? FirebaseFirestore.instance;
  final User user;
  final String role;
  final FirebaseFirestore db;
  late Manager manager;
  int revision = 0;
  String? status;
  bool flushing = false;
  bool processing = false;
  bool closed = false;
  bool writing = false;
  bool revoked = false;
  List<DataRow> outbox = [];
  List<DataRow> commands = [];
  StreamSubscription? _stateSub;
  StreamSubscription? _commandsSub;
  StreamSubscription? _memberSub;
  Timer? _retry;
  String get scope => '${FirebaseConfig.workspace}:${user.uid}:$role';
  String get outboxKey => 'zizouit_outbox:$scope';
  DocumentReference<Map<String, dynamic>> get workspace =>
      db.collection('workspaces').doc(FirebaseConfig.workspace);
  DocumentReference<Map<String, dynamic>> state(String name) =>
      workspace.collection('state').doc(name);
  bool get admin => role == 'المدير';
  String canonical = '';

  Future<void> start() async {
    final member = await workspace
        .collection('members')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));
    if (member.data()?['role'] != role || member.data()?['active'] != true)
      throw RuleViolation('الحساب ما عندوش صلاحية فهاد التعاونية');
    final prefs = SharedPreferencesAsync();
    final queued = await prefs.getString(outboxKey);
    if (queued != null) outbox = (jsonDecode(queued) as List).cast<DataRow>();
    final remote = await state(admin ? 'private' : 'public')
        .get(const GetOptions(source: Source.server));
    canonical =
        remote.data()?['json'] as String? ??
        jsonEncode(Manager(save: (_) async {}).data);
    revision = (remote.data()?['revision'] as num?)?.toInt() ?? 0;
    manager = Manager(save: save, initial: canonical, authenticatedRole: role);
    await storage.writeData(canonical, scope: scope);
    _memberSub = workspace
        .collection('members')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.data()?['active'] != true ||
                snapshot.data()?['role'] != role) {
              revoked = true;
              status = 'الصلاحية تبدلات';
              notifyListeners();
            }
          },
          onError: (Object error) {
            revoked = true;
            notifyListeners();
          },
        );
    _stateSub = state(admin ? 'private' : 'public').snapshots().listen(
      (snapshot) {
        if (closed || writing || manager.busy) return;
        final data = snapshot.data();
        if (data == null) return;
        final nextRevision = (data['revision'] as num).toInt();
        if (nextRevision < revision) return;
        try {
          final json = data['json'] as String;
          Manager.decode(json);
          canonical = json;
          revision = nextRevision;
          manager.applyRemote(json);
          // No fire-and-forget disk overwrite can race an administrator's save.
          status = 'المعطيات متزامنة';
          notifyListeners();
        } catch (_) {
          status = 'وصلت معطيات غير صالحة؛ تواصل مع المدير';
          notifyListeners();
        }
      },
      onError: (Object error) {
        if (error is FirebaseException && error.code == 'permission-denied')
          revoked = true;
        status = 'تعذرت المزامنة؛ تحقق من الاتصال والصلاحيات';
        notifyListeners();
      },
    );
    final query = admin
        ? workspace.collection('commands').where('status', isEqualTo: 'pending')
        : workspace.collection('commands').where('uid', isEqualTo: user.uid);
    _commandsSub = query.snapshots().listen(
      (snapshot) {
        commands = snapshot.docs
            .map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id})
            .toList();
        commands.sort(
          (a, b) => ((a['created'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
              .compareTo(
                (b['created'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
              ),
        );
        notifyListeners();
        if (admin) unawaited(processCommands());
      },
      onError: (Object error) {
        status = 'تعذر تحميل العمليات';
        notifyListeners();
      },
    );
    _retry = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!closed) {
        unawaited(flush());
        if (admin) unawaited(processCommands());
      }
    });
    unawaited(flush());
  }

  Future<void> save(String json) async {
    if (closed || revoked)
      throw RuleViolation('الجلسة تسدات أو الصلاحية تبدلات');
    if (processing)
      throw RuleViolation('تسنى حتى تتعالج العمليات الجاية من الأجهزة');
    if (admin) {
      Manager.decode(json);
      checkSize(json);
      final expected = revision;
      writing = true;
      try {
        await db.runTransaction((tx) async {
          final member = await tx.get(
            workspace.collection('members').doc(user.uid),
          );
          if (member.data()?['role'] != 'المدير' ||
              member.data()?['active'] != true)
            throw RuleViolation('صلاحية المدير تبدلات');
          final current = await tx.get(state('private'));
          final actual = (current.data()?['revision'] as num?)?.toInt() ?? 0;
          if (actual != expected)
            throw RuleViolation(
              'جهاز آخر بدل البيانات؛ حدث المعطيات وعاود العملية',
            );
          writeState(tx, json, actual + 1);
        }, maxAttempts: 3);
        canonical = json;
        revision = expected + 1;
        status = 'المعطيات متزامنة';
      } finally {
        writing = false;
      }
      // The committed cloud transaction is authoritative; a local cache failure must not roll it back.
      try {
        await storage.writeData(json, scope: scope);
      } catch (_) {
        status = 'تزامنت العملية؛ تعذر تحديث النسخة المحلية';
      }
    } else {
      final command = manager.currentCommand;
      if (command == null)
        throw RuleViolation('هاد العملية ما مدعماش المزامنة لهاذ الدور');
      if (utf8.encode(jsonEncode(command)).length > 100000)
        throw RuleViolation('العملية كبيرة؛ قسمها لدفعات');
      final entry = <String, dynamic>{
        'id':
            '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}',
        'kind': command['kind'],
        'arguments': command['arguments'],
      };
      final next = [...outbox, entry];
      await SharedPreferencesAsync().setString(outboxKey, jsonEncode(next));
      outbox = next;
      manager.applyRemote(canonical);
      status = 'تسجلات فطابور المزامنة؛ المخزون كيتحدث من بعد المعالجة';
      unawaited(flush());
    }
    notifyListeners();
  }

  void checkSize(String json) {
    if (utf8.encode(json).length > 750000)
      throw RuleViolation(
        'البيانات تجاوزت حجم النسخة الحالية؛ خاص ترقية تخزين الخادم قبل المتابعة',
      );
  }

  void writeState(Transaction tx, String json, int next) {
    checkSize(json);
    final common = {'revision': next, 'updated': FieldValue.serverTimestamp()};
    tx.set(state('private'), {...common, 'json': json});
    tx.set(state('public'), {...common, 'json': publicSnapshot(json)});
  }

  Future<void> refresh() async {
    if (manager.busy || writing || closed) return;
    final remote = await state(admin ? 'private' : 'public')
        .get(const GetOptions(source: Source.server));
    if (remote.data() == null) return;
    canonical = remote.data()!['json'] as String;
    revision = (remote.data()!['revision'] as num).toInt();
    manager.applyRemote(canonical);
    notifyListeners();
  }

  Future<void> flush() async {
    if (flushing || closed || outbox.isEmpty) return;
    flushing = true;
    try {
      while (outbox.isNotEmpty && !closed) {
        final entry = outbox.first;
        final ref = workspace.collection('commands').doc(entry['id']);
        // A server read makes retries idempotent after an acknowledgement or local-save failure.
        final existing = await ref
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        if (!existing.exists) {
          await ref
              .set({
                'uid': user.uid,
                'kind': entry['kind'],
                'arguments': entry['arguments'],
                'status': 'pending',
                'created': FieldValue.serverTimestamp(),
              })
              .timeout(const Duration(seconds: 10));
        }
        final next = outbox.skip(1).toList();
        await SharedPreferencesAsync().setString(outboxKey, jsonEncode(next));
        outbox = next;
      }
      status = 'العمليات وصلات؛ كتتعالج ملي جهاز المدير متصل';
    } catch (_) {
      status = 'عمليات محفوظة فالجهاز، غادي تعاود المزامنة';
    } finally {
      flushing = false;
      if (!closed) notifyListeners();
    }
  }

  Future<void> processCommands() async {
    if (!admin || processing || closed || writing || manager.busy) return;
    processing = true;
    try {
      for (final queued in List<DataRow>.from(commands)) {
        if (closed || writing || manager.busy) break;
        final ref = workspace.collection('commands').doc(queued['id']);
        await db
            .runTransaction((tx) async {
              final command = await tx.get(ref);
              if (command.data()?['status'] != 'pending') return;
              final payload = command.data()!;
              final member = await tx.get(
                workspace.collection('members').doc(payload['uid']),
              );
              final current = await tx.get(state('private'));
              final role = member.data()?['role'];
              try {
                if (member.data()?['active'] != true || !roles.contains(role))
                  throw RuleViolation('الحساب غير مفعل');
                final initial =
                    current.data()?['json'] as String? ??
                    jsonEncode(Manager(save: (_) async {}).data);
                String? result;
                final processor = Manager(
                  save: (json) async {
                    result = json;
                  },
                  initial: initial,
                  authenticatedRole: role as String,
                );
                await replayCommand(processor, payload);
                if (result == null) throw RuleViolation('العملية غير صالحة');
                final audit = processor.rows('audit').last;
                audit['uid'] = payload['uid'];
                final authoritative = processor.export();
                writeState(
                  tx,
                  authoritative,
                  ((current.data()?['revision'] as num?)?.toInt() ?? 0) + 1,
                );
                tx.update(ref, {
                  'status': 'applied',
                  'processed': FieldValue.serverTimestamp(),
                  'processedBy': user.uid,
                });
              } on RuleViolation catch (error) {
                tx.update(ref, {
                  'status': 'rejected',
                  'error': error.message,
                  'processed': FieldValue.serverTimestamp(),
                  'processedBy': user.uid,
                });
              } on TypeError catch (_) {
                tx.update(ref, {
                  'status': 'rejected',
                  'error': 'معطيات العملية غير صالحة',
                  'processed': FieldValue.serverTimestamp(),
                  'processedBy': user.uid,
                });
              }
            }, maxAttempts: 5)
            .timeout(const Duration(seconds: 30));
      }
      await refresh();
    } catch (_) {
      status = 'تعذرت معالجة الطابور؛ غادي نعاود المحاولة';
    } finally {
      processing = false;
      if (!closed) notifyListeners();
    }
  }

  Future<void> setMember(String uid, String assignedRole) async {
    if (!admin || !roles.contains(assignedRole) || uid.trim().isEmpty)
      throw RuleViolation('صلاحية غير صالحة');
    await workspace.collection('members').doc(uid.trim()).set({
      'role': assignedRole,
      'active': true,
    });
  }

  Future<void> signOut() async {
    if (manager.busy || writing || processing)
      throw RuleViolation('تسنى حتى تسالي العملية الحالية');
    await stop();
    try {
      await storage.removeData(scope);
    } finally {
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> stop() async {
    closed = true;
    _retry?.cancel();
    await _stateSub?.cancel();
    await _commandsSub?.cancel();
    await _memberSub?.cancel();
  }
}
