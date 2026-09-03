import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/media/data/photo_repository.dart';

/// A photo is the one thing in this app PowerSync cannot reconcile later —
/// storage objects are not rows. So the queue is what makes taking a progress
/// photo on a train work, and the object path is what keeps it private.
void main() {
  late SakamaDatabase db;
  late PhotoRepository repo;
  late Directory tmp;

  setUp(() async {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = PhotoRepository(db);
    tmp = await Directory.systemTemp.createTemp('sakama-photo-test');
  });
  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// A real JPEG start-of-image marker, because enqueue now checks it.
  Future<File> aFile([String name = 'p.jpg']) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);
    return f;
  }

  group('the object path, which IS the server-side boundary', () {
    test('is <user_id>/<something>.jpg', () {
      final p = repo.pathForTesting(userId: 'u-1')!;
      expect(p.split('/').first, 'u-1',
          reason: 'storage policies authorise on the FIRST path segment');
      expect(p.endsWith('.jpg'), isTrue);
    });

    test('is always .jpg, because we declare the MIME type ourselves', () {
      // The bucket allowlist checks the declared Content-Type, not the bytes,
      // so the app is what makes the declaration true.
      expect(repo.pathForTesting(userId: 'u-1')!.endsWith('.jpg'), isTrue);
    });

    test('two photos never collide', () {
      final a = repo.pathForTesting(userId: 'u-1');
      final b = repo.pathForTesting(userId: 'u-1');
      expect(a, isNot(b));
    });

    test('there is NO path for a signed-out user', () {
      // Not a fallback path, not "local" — none. Any path we invented would be
      // refused by the policy forever, so a queued photo would be a guaranteed
      // permanent failure rather than an obvious refusal now.
      expect(repo.pathForTesting(userId: null), isNull);
      expect(repo.pathForTesting(userId: ''), isNull);
    });
  });

  group('queueing', () {
    test('returns the path the photo will have, before it is uploaded',
        () async {
      final f = await aFile();
      final path =
          await repo.enqueue(localPath: f.path, kind: PhotoKind.progress, userId: 'u-1');

      expect(path, startsWith('u-1/'));
      final row = (await repo.pending()).single;
      expect(row.remotePath, path,
          reason: 'the row can be written now and render from this later');
      expect(row.bucket, 'progress-photos');
      expect(row.attempts, 0);
    });

    test('a signed-out capture is refused rather than queued', () async {
      final f = await aFile();
      final path =
          await repo.enqueue(localPath: f.path, kind: PhotoKind.meal, userId: null);

      expect(path, isNull);
      expect(await repo.pending(), isEmpty,
          reason: 'a row that can never upload is worse than no row');
    });

    test('the two kinds go to different buckets', () async {
      final a = await aFile('a.jpg');
      final b = await aFile('b.jpg');
      await repo.enqueue(localPath: a.path, kind: PhotoKind.progress, userId: 'u-1');
      await repo.enqueue(localPath: b.path, kind: PhotoKind.meal, userId: 'u-1');

      final buckets = (await repo.pending()).map((r) => r.bucket).toSet();
      expect(buckets, {'progress-photos', 'meal-photos'});
    });

    test('oldest first — the order they were taken', () async {
      var t = DateTime(2026, 9, 3, 8);
      final r = PhotoRepository(db, now: () => t);
      for (final n in ['first', 'second', 'third']) {
        final f = await aFile('$n.jpg');
        await r.enqueue(localPath: f.path, kind: PhotoKind.meal, userId: 'u-1');
        t = t.add(const Duration(minutes: 1));
      }
      final order =
          (await r.pending()).map((e) => e.localPath.split('/').last).toList();
      expect(order, ['first.jpg', 'second.jpg', 'third.jpg']);
    });
  });

  group('draining', () {
    test('a success removes the row AND the local file', () async {
      final f = await aFile();
      await repo.enqueue(localPath: f.path, kind: PhotoKind.meal, userId: 'u-1');

      await repo.markDone((await repo.pending()).single);

      expect(await repo.pending(), isEmpty);
      expect(f.existsSync(), isFalse,
          reason: 'the local copy existed only to survive being offline');
    });

    test('a failure KEEPS the row and the file, and counts the attempt',
        () async {
      final f = await aFile();
      await repo.enqueue(localPath: f.path, kind: PhotoKind.progress, userId: 'u-1');

      await repo.markFailed((await repo.pending()).single, 'no network');

      final row = (await repo.pending()).single;
      expect(row.attempts, 1);
      expect(row.lastError, contains('no network'));
      expect(f.existsSync(), isTrue,
          reason: 'deleting on failure is how you lose the photo');
    });

    test('attempts accumulate, so a stuck upload is visible not invisible',
        () async {
      final f = await aFile();
      await repo.enqueue(localPath: f.path, kind: PhotoKind.meal, userId: 'u-1');
      for (var i = 0; i < 3; i++) {
        await repo.markFailed((await repo.pending()).single, 'still offline');
      }
      expect((await repo.pending()).single.attempts, 3);
    });

    test('a photo whose file is gone is dropped, not retried forever',
        () async {
      final f = await aFile();
      await repo.enqueue(localPath: f.path, kind: PhotoKind.meal, userId: 'u-1');
      await f.delete();

      expect(await repo.dropIfFileMissing((await repo.pending()).single), isTrue);
      expect(await repo.pending(), isEmpty,
          reason: 'a queue that cannot drain is worse than an honest loss');
    });

    test('a photo whose file is present is NOT dropped', () async {
      final f = await aFile();
      await repo.enqueue(localPath: f.path, kind: PhotoKind.meal, userId: 'u-1');

      expect(await repo.dropIfFileMissing((await repo.pending()).single), isFalse);
      expect((await repo.pending()).length, 1);
    });

    test('deleting the row survives a file that will not delete', () async {
      // markDone must not resurrect the row because cleanup failed.
      final f = await aFile();
      await repo.enqueue(localPath: f.path, kind: PhotoKind.meal, userId: 'u-1');
      final row = (await repo.pending()).single;
      await f.delete(); // gone before markDone tries

      await repo.markDone(row);
      expect(await repo.pending(), isEmpty);
    });
  });

  group('the two photo kinds', () {
    test('only progress photos need a signed URL', () {
      expect(PhotoKind.progress.signedUrl, isTrue,
          reason: 'a body photo is not a durable link');
      expect(PhotoKind.meal.signedUrl, isFalse);
    });

    test('the signed-URL life is minutes, not days', () {
      // A signed URL is a bearer token in a string: whoever holds it can fetch
      // the object with no account at all.
      expect(progressUrlTtl.inMinutes, lessThanOrEqualTo(15));
      expect(progressUrlTtl.inSeconds, greaterThan(0));
    });

    test('the bucket names match the migration exactly', () {
      expect(PhotoKind.progress.bucket, 'progress-photos');
      expect(PhotoKind.meal.bucket, 'meal-photos');
    });
  });

  test('the queue is ordinary local rows here — the no-crud-op property lives '
      'in the sync contract test', () async {
    // Named honestly after review: this runs on NativeDatabase.memory(), where
    // PowerSync's ps_crud table does not exist, so it CANNOT observe whether a
    // write produces a crud op. Flipping Table.localOnly to Table() would not
    // redden it. The real guard is test/db/sync_contract_test.dart, which
    // checks the publication, RLS and stream expectations per table.
    final f = await aFile();
    await repo.enqueue(localPath: f.path, kind: PhotoKind.progress, userId: 'u-1');
    expect((await repo.pending()).length, 1);
  });

  /// THE BLOCKING FINDING FROM REVIEW. PowerSync's clear deliberately preserves
  /// local-only tables, so without this a queued progress photo — a picture of
  /// the DEPARTING user's body — survives into the next person's session, and
  /// they can neither upload it (the path's first segment is the old uid) nor
  /// get rid of it.
  group('identity change', () {
    test('clearAll drops the rows AND the files', () async {
      final a = await aFile('a.jpg');
      final b = await aFile('b.jpg');
      await repo.enqueue(localPath: a.path, kind: PhotoKind.progress, userId: 'A');
      await repo.enqueue(localPath: b.path, kind: PhotoKind.meal, userId: 'A');

      await repo.clearAll();

      expect(await repo.pending(), isEmpty);
      expect(a.existsSync(), isFalse,
          reason: 'rows without files would leave the images unreachable AND '
              'unreapable');
      expect(b.existsSync(), isFalse);
    });

    test('a file that will not delete does not strand the rest of the wipe',
        () async {
      final a = await aFile('a.jpg');
      final b = await aFile('b.jpg');
      await repo.enqueue(localPath: a.path, kind: PhotoKind.progress, userId: 'A');
      await repo.enqueue(localPath: b.path, kind: PhotoKind.progress, userId: 'A');
      await a.delete(); // already gone when clearAll reaches it

      await repo.clearAll();
      expect(await repo.pending(), isEmpty);
      expect(b.existsSync(), isFalse);
    });

    test('clearing an empty queue is harmless', () async {
      await repo.clearAll();
      expect(await repo.pending(), isEmpty);
    });
  });

  /// The name promises JPEG and the bucket validates only the DECLARED type,
  /// so this is the one place the promise can be kept.
  group('what may be queued', () {
    test('a file that is not JPEG is refused', () async {
      final heic = File('${tmp.path}/x.jpg');
      await heic.writeAsBytes([0x00, 0x00, 0x00, 0x18]); // HEIC-ish, not FF D8
      expect(
          await repo.enqueue(
              localPath: heic.path, kind: PhotoKind.meal, userId: 'u-1'),
          isNull);
      expect(await repo.pending(), isEmpty);
    });

    test('a file that does not exist is refused', () async {
      expect(
          await repo.enqueue(
              localPath: '${tmp.path}/nope.jpg', kind: PhotoKind.meal, userId: 'u-1'),
          isNull);
      expect(await repo.pending(), isEmpty);
    });
  });

  /// The attempt counter was a number nobody read. A row that can never
  /// succeed would otherwise retry until the app was deleted.
  group('giving up', () {
    test('the limit is a NUMBER, not whatever the constant happens to be', () {
      // Looping `maxAttempts` times and asserting it stopped is a tautology:
      // raising the constant just loops more. Review caught this exact shape on
      // #159, so the value is pinned.
      expect(PhotoRepository.maxAttempts, 8);
    });

    test('a photo past the limit stops being drainable', () async {
      final f = await aFile();
      await repo.enqueue(localPath: f.path, kind: PhotoKind.meal, userId: 'u-1');
      for (var i = 0; i < 8; i++) {
        await repo.markFailed((await repo.pending()).single, 'offline');
      }

      expect(await repo.drainable(), isEmpty);
      expect((await repo.stuck()).length, 1,
          reason: 'it is surfaced, not silently dropped');
      expect((await repo.pending()).length, 1,
          reason: 'the photo is still on disk and still theirs');
    });

    test('a photo below the limit is still drainable', () async {
      final f = await aFile();
      await repo.enqueue(localPath: f.path, kind: PhotoKind.meal, userId: 'u-1');
      await repo.markFailed((await repo.pending()).single, 'offline');

      expect((await repo.drainable()).length, 1);
      expect(await repo.stuck(), isEmpty);
    });
  });
}
