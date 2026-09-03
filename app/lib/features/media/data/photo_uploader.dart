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

  @override
  Future<void> upload({
    required String bucket,
    required String remotePath,
    required File file,
  }) async {
    await _supabase.storage.from(bucket).upload(
          remotePath,
          file,
          // DECLARED EXPLICITLY, because the bucket's allowlist validates this
          // header and not the bytes. `enqueue` already refused anything that
          // is not really a JPEG, so this declaration is one we have earned.
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
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

  /// Everything drainable went up.
  done,

  /// Some went up, some did not — offline, or the server refused.
  partial,

  /// Not attempted: there is nobody to upload as.
  signedOut,

  /// Already running. Two drains would upload the same object twice and race
  /// on the rows.
  busy,
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
          await repo.markFailed(row, e);
        }
      }
      return failed == 0 ? DrainOutcome.done : DrainOutcome.partial;
    } finally {
      _draining = false;
    }
  }

  /// A URL the UI can render.
  ///
  /// Progress photos get a short-lived signed URL — the sensitive class, where
  /// a durable link would be a bearer token for a picture of someone's body.
  /// Meal photos are private too, but an ordinary authenticated fetch is
  /// proportionate, so they are read through the SDK rather than a URL.
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
