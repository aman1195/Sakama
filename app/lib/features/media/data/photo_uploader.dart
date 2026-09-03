import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'photo_repository.dart';

/// The narrow slice of object storage this app needs.
///
/// Ours, not the SDK's, for the same reason [SpeechEngine] is an interface:
/// the drainer below is where the decisions live, and it has to be testable
/// without a network, a bucket, or a signed-in user.
abstract class PhotoStorage {
  /// Upload [file] to [remotePath] in [bucket]. Throws on failure.
  Future<void> upload({
    required String bucket,
    required String remotePath,
    required File file,
  });

  /// A short-lived URL for a private object.
  Future<String> signedUrl({
    required String bucket,
    required String remotePath,
    required Duration ttl,
  });
}

class SupabasePhotoStorage implements PhotoStorage {
  SupabasePhotoStorage({SupabaseClient? client})
      : _client = client; // ignore: prefer_initializing_formals
  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  /// The options every upload goes out with.
  ///
  /// EXTRACTED SO IT CAN BE TESTED. Both lines here are decisions that are
  /// invisible through the [PhotoStorage] interface, and a fake cannot observe
  /// either — review found the first version of the upsert test proving only
  /// that the fake threw.
  @visibleForTesting
  static const fileOptions = FileOptions(
    // DECLARED EXPLICITLY, because the bucket's allowlist validates this
    // header and not the bytes. `enqueue` already refused anything without a
    // JPEG marker, so it is a declaration we have earned rather than one we
    // hope is true.
    contentType: 'image/jpeg',
    // IDEMPOTENT ON PURPOSE. The SDK default is false, which throws 409
    // Duplicate if the object exists — and the retry path reaches that case
    // routinely: the upload succeeds, the response is lost to a backgrounded
    // app or a dropped connection, and the next drain sends the SAME path
    // because it is pinned on the row at capture. Without this, a photo that
    // genuinely uploaded burns every attempt on 409s, ends up in stuck(), and
    // leaves its local copy on disk forever.
    //
    // Overwriting is safe here in a way it usually is not: the path is
    // `<uid>/<fresh v4 uuid>.jpg`, minted once per photo, so the only object
    // it can ever collide with is that same photo's own earlier upload.
    upsert: true,
  );

  @override
  Future<void> upload({
    required String bucket,
    required String remotePath,
    required File file,
  }) async {
    await _supabase.storage
        .from(bucket)
        .upload(remotePath, file, fileOptions: fileOptions);
  }

  @override
  Future<String> signedUrl({
    required String bucket,
    required String remotePath,
    required Duration ttl,
  }) =>
      _supabase.storage.from(bucket).createSignedUrl(remotePath, ttl.inSeconds);
}

/// Why a drain stopped, so the caller can tell "done" from "not now".
enum DrainOutcome {
  /// Nothing was waiting.
  empty,

  /// The queue is empty now.
  ///
  /// NOT "everything was uploaded" — a drain that only reaped missing files or
  /// dropped another account's rows also ends here. A caller must not render
  /// "all your photos are backed up" from this.
  done,

  /// Some went up, some did not — offline, or the server refused.
  partial,

  /// Not attempted: there is nobody to upload as.
  signedOut,

  /// Already running. Two drains would upload the same object twice and race
  /// on the rows.
  busy,
}

/// Is this failure worth trying again?
///
/// A permanent refusal and a dead network look identical to a catch-all, and
/// treating them the same means eight pointless round trips before a row that
/// could never succeed is finally set aside.
bool isPermanent(Object error) {
  if (error is! StorageException) return false;
  // 401/403: the policy refused us. The path is fixed on the row, so the same
  // request will be refused for as long as the row exists.
  return error.statusCode == '401' || error.statusCode == '403';
}

/// Moves queued photos into storage, and gets links back out.
///
/// NEVER BLOCKS ANYTHING. A drain is background work the user did not ask for:
/// it is called on sign-in and on reconnect, it swallows its own failures, and
/// a photo that will not upload leaves a row behind rather than an error in
/// front of someone trying to log lunch.
class PhotoUploader {
  PhotoUploader({
    required this.repo,
    required this.storage,
    required this.currentUserId,
  });

  final PhotoRepository repo;
  final PhotoStorage storage;

  /// Read at drain time, never captured: a photo must be uploaded as whoever
  /// is signed in NOW, not whoever was when this was constructed.
  final String? Function() currentUserId;

  bool _draining = false;

  /// Try to upload everything that is waiting.
  Future<DrainOutcome> drain() async {
    if (_draining) return DrainOutcome.busy;
    final uid = currentUserId();
    if (uid == null || uid.isEmpty) return DrainOutcome.signedOut;

    _draining = true;
    try {
      return await _drain(uid);
    } catch (e) {
      // The class promises it swallows its own failures, and the database
      // calls sit outside the per-photo try. A Drift error on a locked file
      // must not surface from fire-and-forget background work.
      debugPrint('photo: drain failed: $e');
      return DrainOutcome.partial;
    } finally {
      _draining = false;
    }
  }

  Future<DrainOutcome> _drain(String uid) async {
    {
      final rows = await repo.drainable();
      if (rows.isEmpty) return DrainOutcome.empty;

      var failed = 0;
      for (final row in rows) {
        // A file the OS reclaimed can never upload. Reaping it is how the
        // queue stays drainable instead of accumulating permanent residue.
        if (await repo.dropIfFileMissing(row)) continue;

        // BELT AND BRACES AGAINST UPLOADING ONE USER'S PHOTO AS ANOTHER. The
        // identity-change wipe should have cleared these already, but if it
        // ever failed, this row would be refused by the storage policy forever
        // and burn attempts doing it. Refusing here is the same answer, and it
        // does not touch the network.
        if (!row.remotePath.startsWith('$uid/')) {
          debugPrint('photo: dropping a queued photo owned by another account');
          await repo.markDone(row); // drops the row AND the file
          continue;
        }

        try {
          await storage.upload(
            bucket: row.bucket,
            remotePath: row.remotePath,
            file: File(row.localPath),
          );
          await repo.markDone(row);
        } catch (e) {
          failed++;
          // A refusal is not a retry. Setting it aside at once keeps the queue
          // honest — stuck() shows a photo that needs explaining, instead of
          // one that looks like it is still trying.
          await (isPermanent(e)
              ? repo.markPermanentlyFailed(row, e)
              : repo.markFailed(row, e));
        }
      }
      return failed == 0 ? DrainOutcome.done : DrainOutcome.partial;
    }
  }

  /// A URL the UI can render.
  ///
  /// Progress photos get a short-lived signed URL — the sensitive class, where
  /// a durable link would be a bearer token for a picture of someone's body.
  ///
  /// MEAL PHOTOS GET NOTHING YET, and null here is a gap rather than a design.
  /// Their bucket is private too, so `getPublicUrl` returns a URL that fails —
  /// the obvious-looking alternative is the wrong one. A read path (an
  /// authenticated download, or a longer-lived signed URL) lands with the
  /// gallery that needs it; until then there is no way to display one.
  ///
  /// Returns null rather than throwing: a photo that will not load is a broken
  /// thumbnail, never a broken screen.
  Future<String?> urlFor({
    required PhotoKind kind,
    required String remotePath,
  }) async {
    if (!kind.signedUrl) return null;
    try {
      return await storage.signedUrl(
        bucket: kind.bucket,
        remotePath: remotePath,
        ttl: progressUrlTtl,
      );
    } catch (e) {
      debugPrint('photo: could not sign $remotePath: $e');
      return null;
    }
  }
}
