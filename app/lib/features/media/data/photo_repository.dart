import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
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
  PhotoRepository(this._db, {Uuid? uuid, DateTime Function()? now})
      : _uuid = uuid ?? const Uuid(),
        _now = now ?? DateTime.now;

  final SakamaDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _now;

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
  String? pathFor({required String? userId}) =>
      (userId == null || userId.isEmpty) ? null : '$userId/${_uuid.v4()}.jpg';

  /// Queue a captured photo for upload.
  ///
  /// Returns the object path the photo WILL have, so the caller can store it
  /// on its row now and render from it later — the row and the object are
  /// written independently, and neither waits for the other.
  Future<String?> enqueue({
    required String localPath,
    required PhotoKind kind,
    required String? userId,
  }) async {
    final remote = pathFor(userId: userId);
    if (remote == null) {
      debugPrint('photo: not queued — no signed-in user to file it under');
      return null;
    }
    await _db.into(_db.pendingUploads).insert(PendingUploadsCompanion.insert(
          id: _uuid.v4(),
          bucket: kind.bucket,
          localPath: localPath,
          remotePath: remote,
          createdAt: _now().millisecondsSinceEpoch,
        ));
    return remote;
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
      final f = File(row.localPath);
      if (f.existsSync()) await f.delete();
    } catch (e) {
      // A leftover file costs disk. Failing here must not resurrect the row.
      debugPrint('photo: could not delete local copy: $e');
    }
  }

  /// Failed. Keep the row, record why, and count the attempt.
  Future<void> markFailed(PendingUploadRow row, Object error) =>
      (_db.update(_db.pendingUploads)..where((t) => t.id.equals(row.id))).write(
        PendingUploadsCompanion(
          attempts: Value(row.attempts + 1),
          lastError: Value(error.toString()),
        ),
      );

  /// Give up on a photo whose file is gone.
  ///
  /// If the user cleared storage or the OS reclaimed the file, retrying
  /// forever is a loop with no exit. The row goes; the photo is genuinely
  /// lost, and pretending otherwise would show a queue that never drains.
  Future<bool> dropIfFileMissing(PendingUploadRow row) async {
    if (File(row.localPath).existsSync()) return false;
    await (_db.delete(_db.pendingUploads)..where((t) => t.id.equals(row.id))).go();
    return true;
  }
}
