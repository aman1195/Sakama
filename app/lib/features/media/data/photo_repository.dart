import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/database.dart';

/// Where a photo goes, and what it is worth protecting from.
///
/// Two buckets because the two photos are not the same risk (migration
/// 20260903000015). This enum is the only place the app names them, so a
/// progress photo cannot end up in the gallery bucket by a typo.
enum PhotoKind {
  /// A picture of the user's body. Reached only through a short-lived signed
  /// URL, never a durable link.
  progress('progress-photos', signedUrl: true),

  /// A plate of food, for the gallery.
  meal('meal-photos', signedUrl: false);

  const PhotoKind(this.bucket, {required this.signedUrl});
  final String bucket;

  /// Whether reading requires a signed URL rather than an ordinary
  /// authenticated fetch. True for the sensitive class.
  final bool signedUrl;
}

/// How long a progress-photo link stays valid.
///
/// Short on purpose. A signed URL is a bearer token in a string: whoever holds
/// it can fetch the object with no account at all, so it lives long enough to
/// render a screen and not long enough to be worth keeping. Minutes, not days.
const progressUrlTtl = Duration(minutes: 5);

/// The queue and the naming rules for stored photos.
///
/// THE OBJECT PATH IS THE SECURITY BOUNDARY. Server-side, the storage policies
/// authorise on the first path segment: an object at `<uid>/…` is reachable by
/// that user and nobody else, and anything written elsewhere is refused
/// outright. So the path is computed here, once, and pinned into the queue row
/// at capture time — never re-derived at upload time, when the signed-in
/// account may have changed.
class PhotoRepository {
  PhotoRepository(
    this._db, {
    Uuid? uuid,
    DateTime Function()? now,
    Future<Directory> Function()? photoDir,
  })  : _uuid = uuid ?? const Uuid(),
        _now = now ?? DateTime.now,
        _photoDir = photoDir ?? _defaultPhotoDir;

  final SakamaDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _now;
  final Future<Directory> Function() _photoDir;

  /// Where queued photos live, resolved fresh every time.
  ///
  /// NEVER PERSISTED. iOS does not guarantee the application container path
  /// across an install or an update, so a stored absolute path can stop
  /// resolving while the file is fine at the new location. Rows hold a NAME;
  /// this turns it into a file. Same reasoning as sync_service resolving the
  /// database path at open rather than remembering it.
  static Future<Directory> _defaultPhotoDir() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'photos'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// The file a queued row refers to, right now.
  Future<File> fileFor(PendingUploadRow row) async =>
      File(p.join((await _photoDir()).path, row.localName));

  /// Where a newly captured photo should be written.
  Future<File> newFileFor(String name) async =>
      File(p.join((await _photoDir()).path, name));

  /// The object path for a new photo.
  ///
  /// `<user_id>/<uuid>.jpg`, and the extension is always `.jpg` because the
  /// upload is always re-encoded JPEG — the bucket's MIME allowlist checks the
  /// declared Content-Type, not the bytes, so the app is what makes the
  /// declaration true.
  ///
  /// Returns null with no signed-in user. A photo cannot be filed under
  /// "nobody": there is no path that would satisfy the policy, so queueing one
  /// would guarantee a permanent failure instead of an obvious refusal.
  ///
  /// PRIVATE, because every call mints a NEW uuid. A public version invited
  /// the reasonable-looking `final p = pathFor(...); enqueue(...)`, which
  /// stores one path on the row and uploads to another — a permanently broken
  /// image and an orphaned object. [enqueue] returns the path it actually
  /// used; that is the only way to obtain one.
  @visibleForTesting
  String? pathForTesting({required String? userId}) => _pathFor(userId: userId);

  String? _pathFor({required String? userId}) =>
      (userId == null || userId.isEmpty) ? null : '$userId/${_uuid.v4()}.jpg';

  /// Queue a captured photo for upload.
  ///
  /// Returns the object path the photo WILL have, so the caller can store it
  /// on its row now and render from it later — the row and the object are
  /// written independently, and neither waits for the other.
  Future<String?> enqueue({
    required String localName,
    required PhotoKind kind,
    required String? userId,
  }) async {
    final remote = _pathFor(userId: userId);
    if (remote == null) {
      debugPrint('photo: not queued — no signed-in user to file it under');
      return null;
    }
    // THE NAME PROMISES JPEG, SO CHECK IT. The object is uploaded as
    // `image/jpeg`, and the bucket's allowlist validates that DECLARED type
    // rather than the bytes (measured in #160) — so nothing server-side stops
    // a HEIC straight from the picker being stored under a .jpg name as
    // image/jpeg, where it renders for nobody. Two bytes of check here is the
    // only place that promise can be kept.
    final file = await newFileFor(localName);
    if (!await _looksLikeJpeg(file)) {
      debugPrint('photo: not queued — $localName is not JPEG');
      return null;
    }
    // ALREADY QUEUED? Hand back the path it already has.
    //
    // A double-tap on save would otherwise make two rows for one file, and the
    // pair degrades badly: whichever uploads first deletes the file, the other
    // becomes an orphan, and until it is reaped the queue count is wrong. A
    // unique index would answer this by THROWING at capture, which is worse —
    // the user did nothing wrong. Returning the existing path makes a second
    // tap a no-op, which is what they meant.
    final already = await (_db.select(_db.pendingUploads)
          ..where((t) => t.localName.equals(localName)))
        .getSingleOrNull();
    if (already != null) return already.remotePath;
    await _db.into(_db.pendingUploads).insert(PendingUploadsCompanion.insert(
          id: _uuid.v4(),
          bucket: kind.bucket,
          localName: localName,
          remotePath: remote,
          createdAt: Value(_now().millisecondsSinceEpoch),
        ));
    return remote;
  }

  /// JPEG starts with the SOI marker FF D8. Cheap, and enough: this is a
  /// contract check on our own capture path, not a defence against an attacker
  /// who already controls the device.
  Future<bool> _looksLikeJpeg(File f) async {
    try {
      if (!f.existsSync()) return false;
      final head = await f.openRead(0, 2).expand((c) => c).toList();
      return head.length == 2 && head[0] == 0xFF && head[1] == 0xD8;
    } catch (e) {
      debugPrint('photo: could not read ${f.path}: $e');
      return false;
    }
  }

  /// Everything still waiting, oldest first — the order they were taken.
  Future<List<PendingUploadRow>> pending() =>
      (_db.select(_db.pendingUploads)..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Stream<int> watchPendingCount() {
    final q = _db.selectOnly(_db.pendingUploads)
      ..addColumns([_db.pendingUploads.id.count()]);
    return q.map((r) => r.read(_db.pendingUploads.id.count()) ?? 0).watchSingle();
  }

  /// Uploaded. Drop the row, and the file with it.
  ///
  /// The local copy is deleted only AFTER the object is safely in storage —
  /// the whole point of keeping it on disk was to survive the gap.
  Future<void> markDone(PendingUploadRow row) async {
    await (_db.delete(_db.pendingUploads)..where((t) => t.id.equals(row.id))).go();
    try {
      final f = await fileFor(row);
      if (f.existsSync()) await f.delete();
    } catch (e) {
      // A leftover file costs disk. Failing here must not resurrect the row.
      debugPrint('photo: could not delete local copy: $e');
    }
  }

  /// After this many failures a photo is not "retrying", it is stuck.
  ///
  /// The counter existed but nothing read it, which made it a number rather
  /// than a limit. A row whose upload can never succeed — a path that no
  /// longer matches the signed-in user, a bucket that no longer exists —
  /// would otherwise retry until the app was deleted.
  static const maxAttempts = 8;

  /// Photos worth trying again. The drainer reads THIS, not [pending].
  Future<List<PendingUploadRow>> drainable() async =>
      (await pending()).where((r) => r.attempts < maxAttempts).toList();

  /// Photos that have given up, for the UI to explain rather than hide.
  Future<List<PendingUploadRow>> stuck() async =>
      (await pending()).where((r) => r.attempts >= maxAttempts).toList();

  /// Failed. Keep the row, record why, and count the attempt.
  Future<void> markFailed(PendingUploadRow row, Object error) =>
      (_db.update(_db.pendingUploads)..where((t) => t.id.equals(row.id))).write(
        PendingUploadsCompanion(
          attempts: Value(row.attempts + 1),
          lastError: Value(error.toString()),
        ),
      );

  /// Failed in a way that retrying cannot fix.
  ///
  /// Jumps straight to the limit rather than counting up to it. A policy
  /// refusal on a path pinned at capture will be refused identically every
  /// time, so seven more round trips buy nothing and hide the row in
  /// "pending" while they happen.
  Future<void> markPermanentlyFailed(PendingUploadRow row, Object error) =>
      (_db.update(_db.pendingUploads)..where((t) => t.id.equals(row.id))).write(
        PendingUploadsCompanion(
          attempts: Value(maxAttempts),
          lastError: Value(error.toString()),
        ),
      );

  /// Drop every queued photo, files included.
  ///
  /// FOR AN IDENTITY CHANGE, and it belongs on the same signal as the
  /// conversations, the memory and the sync receipts. A queued progress photo
  /// is a picture of the DEPARTING user's body sitting on a shared device.
  /// PowerSync's clear does not reach it — `clearLocal: false` deliberately
  /// preserves local-only tables — so without this it survives into the next
  /// person's session: visible in their queue, and impossible to upload or
  /// remove, because the object path's first segment is the old uid and the
  /// storage policy compares it against theirs. It would retry until the app
  /// was deleted.
  ///
  /// The FILES go too. Dropping the rows alone would leave the images on disk
  /// with nothing left pointing at them, which is worse: unreachable by the
  /// owner and unreapable by us.
  Future<void> clearAll() async {
    for (final row in await pending()) {
      try {
        final f = await fileFor(row);
        if (f.existsSync()) await f.delete();
      } catch (e) {
        // One stubborn file must not strand the rest of the wipe.
        debugPrint('photo: could not delete departing user\'s file: $e');
      }
    }
    await _db.delete(_db.pendingUploads).go();
  }

  /// Give up on a photo whose file is gone.
  ///
  /// If the user cleared storage or the OS reclaimed the file, retrying
  /// forever is a loop with no exit. The row goes; the photo is genuinely
  /// lost, and pretending otherwise would show a queue that never drains.
  Future<bool> dropIfFileMissing(PendingUploadRow row) async {
    if ((await fileFor(row)).existsSync()) return false;
    await (_db.delete(_db.pendingUploads)..where((t) => t.id.equals(row.id))).go();
    return true;
  }
}
