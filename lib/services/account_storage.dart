import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Account keys come only from an authenticated Cognito subject, never email.
class AccountStorage {
  static String keyFor(String? subject) => subject == null
      ? 'signed_out'
      : 'user_${sha256.convert(utf8.encode(subject)).toString()}';

  final Directory root;
  AccountStorage(this.root);
  Directory profile(String key) => Directory('${root.path}/profiles/$key');
  File get binding => File('${root.path}/legacy_owner.json');

  File get _recoveryRequest => File('${root.path}/legacy_recovery_request.json');

  /// Written only after the user explicitly confirms ownership in Settings.
  /// This durable request is saved before any active profile is moved.
  Future<void> authorizeRecovery(String owner) async {
    if (!RegExp(r'^user_[a-f0-9]{64}$').hasMatch(owner)) {
      throw StateError('Recovery requires an authenticated owner.');
    }
    if (await readBinding() != null) {
      throw StateError('Original records already have an owner.');
    }
    if (await _recoveryRequest.exists()) {
      final request = jsonDecode(await _recoveryRequest.readAsString()) as Map;
      if (request['owner'] != owner) {
        throw StateError('A different account has a pending recovery.');
      }
      return;
    }
    await root.create(recursive: true);
    final temporary = File('${_recoveryRequest.path}.tmp');
    await temporary.writeAsString(jsonEncode({
      'owner': owner,
      'archive': DateTime.now().microsecondsSinceEpoch.toString(),
    }), flush: true);
    await temporary.rename(_recoveryRequest.path);
  }

  /// Resumes only a previously confirmed request for this authenticated owner.
  /// Existing profile files are archived, never merged, overwritten or deleted.
  Future<void> completeAuthorizedRecovery(
    String owner, Directory legacy, File recovery,
  ) async {
    if (!await _recoveryRequest.exists()) { return; }
    final request = jsonDecode(await _recoveryRequest.readAsString());
    if (request is! Map || request['owner'] is! String ||
        !RegExp(r'^user_[a-f0-9]{64}$').hasMatch(request['owner']) ||
        request['archive'] is! String ||
        !RegExp(r'^[0-9]+$').hasMatch(request['archive'])) {
      throw const FormatException('Invalid pending local recovery request.');
    }
    if (request['owner'] != owner) { return; }
    final journal = await readBinding();
    if (journal != null && journal['owner'] != owner) {
      throw StateError('Original records belong to another account.');
    }
    if (journal == null) {
      final archive = Directory('${root.path}/preserved_profiles/$owner/${request['archive']}');
      final current = profile(owner);
      if (await current.exists()) {
        if (await archive.exists()) {
          throw StateError('Recovery stopped to preserve both existing profiles.');
        }
        await archive.parent.create(recursive: true);
        await current.rename(archive.path);
      }
    }
    await claim(owner, legacy, recovery);
    await _recoveryRequest.delete();
  }

  Future<Map<String, dynamic>?> readBinding() async {
    if (!await binding.exists()) { return null; }
    final value = jsonDecode(await binding.readAsString());
    if (value is! Map<String, dynamic> ||
        value['owner'] is! String ||
        !RegExp(r'^user_[a-f0-9]{64}$').hasMatch(value['owner']) ||
        !['copying', 'complete'].contains(value['state']) ||
        value['files'] is! Map) {
      throw const FormatException('Invalid original-data migration record.');
    }
    return value;
  }

  Future<void> _save(Map<String, dynamic> value) async {
    await root.create(recursive: true);
    final tmp = File('${binding.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(binding.path);
  }

  /// Preserves the original files and verifies every copied byte.
  Future<void> claim(String owner, Directory legacy, File recovery) async {
    if (!RegExp(r'^user_[a-f0-9]{64}$').hasMatch(owner)) {
      throw StateError('Original data requires an authenticated account.');
    }
    var journal = await readBinding();
    if (journal != null && journal['owner'] != owner) {
      throw StateError('Original data is reserved for another account.');
    }
    if (journal == null) {
      if (await profile(owner).exists()) {
        throw StateError('This account already has local storage. Original files were kept; a reviewed merge is required.');
      }
      final files = <String, dynamic>{};
      await for (final entity in legacy.list(followLinks: false)) {
        if (entity is! File || entity.path.endsWith('.lock')) { continue; }
        final name = entity.uri.pathSegments.last;
        files['.hive/$name'] = {
          'source': entity.path,
          'sha256': sha256.convert(await entity.readAsBytes()).toString(),
        };
      }
      if (files.isEmpty) { throw StateError('No original database files found.'); }
      if (await recovery.exists()) {
        files['cashsense_restore_recovery.json'] = {
          'source': recovery.path,
          'sha256': sha256.convert(await recovery.readAsBytes()).toString(),
        };
      }
      journal = {'owner': owner, 'state': 'copying', 'files': files};
      await _save(journal);
    }
    if (journal['state'] == 'complete') { return; }
    final destination = profile(owner);
    final staging = Directory('${root.path}/migration_$owner');
    final files = Map<String, dynamic>.from(journal['files'] as Map);
    for (final entry in files.entries) {
      final relative = entry.key;
      if (relative.startsWith('/') || relative.split('/').contains('..')) {
        throw const FormatException('Invalid migration file path.');
      }
      final metadata = Map<String, dynamic>.from(entry.value as Map);
      final target = File('${destination.path}/$relative');
      if (!await destination.exists()) {
        final bytes = await File(metadata['source'] as String).readAsBytes();
        if (sha256.convert(bytes).toString() != metadata['sha256']) {
          throw StateError('Original files changed during migration. No original file was removed.');
        }
        final staged = File('${staging.path}/$relative');
        await staged.parent.create(recursive: true);
        await staged.writeAsBytes(bytes, flush: true);
        if (sha256.convert(await staged.readAsBytes()).toString() != metadata['sha256']) {
          throw StateError('Original data copy failed verification.');
        }
      } else if (!await target.exists() ||
          sha256.convert(await target.readAsBytes()).toString() != metadata['sha256']) {
        throw StateError('Incomplete migration could not be verified. Original files were kept.');
      }
    }
    if (!await destination.exists()) {
      await destination.parent.create(recursive: true);
      await staging.rename(destination.path);
    }
    journal['state'] = 'complete';
    await _save(journal);
  }
}
