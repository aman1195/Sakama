import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/media/data/photo_repository.dart';
import 'package:sakama/features/media/data/photo_uploader.dart';

/// The drainer is background work nobody asked for. It must move photos when
/// it can, keep them when it cannot, and never put an error in front of
/// someone trying to log lunch.

class _FakeStorage implements PhotoStorage {
  Object? failWith;
  final uploaded = <String>[];
  final signed = <String>[];

  @override
  Future<void> upload({
    required String bucket,
    required String remotePath,
    required File file,
  }) async {
    if (failWith != null) throw failWith!;
    uploaded.add('$bucket/$remotePath');
  }

  @override
  Future<String> signedUrl({
    required String bucket,
    required String remotePath,
    required Duration ttl,
  }) async {
    if (failWith != null) throw failWith!;
    signed.add('$bucket/$remotePath?ttl=${ttl.inSeconds}');
    return 'https://example.test/$remotePath?token=x';
  }
}

void main() {
  late SakamaDatabase db;
  late PhotoRepository repo;
  late _FakeStorage storage;
  late Directory tmp;
  String? uid = 'u-1';

  setUp(() async {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = PhotoRepository(db);
    storage = _FakeStorage();
    tmp = await Directory.systemTemp.createTemp('sakama-upload-test');
    uid = 'u-1';
  });
  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  PhotoUploader uploader() => PhotoUploader(
      repo: repo, storage: storage, currentUserId: () => uid);

  Future<File> aJpeg([String name = 'p.jpg']) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);
    return f;
  }

  Future<File> queued({PhotoKind kind = PhotoKind.meal, String name = 'p.jpg'}) async {
    final f = await aJpeg(name);
    await repo.enqueue(localPath: f.path, kind: kind, userId: uid);
    return f;
  }

  group('draining', () {
    test('an empty queue says so rather than pretending it worked', () async {
      expect(await uploader().drain(), DrainOutcome.empty);
    });

    test('a photo goes up, and both the row and the file go away', () async {
      final f = await queued(kind: PhotoKind.progress);

      expect(await uploader().drain(), DrainOutcome.done);
      expect(storage.uploaded.single, startsWith('progress-photos/u-1/'));
      expect(await repo.pending(), isEmpty);
      expect(f.existsSync(), isFalse);
    });

    test('a failure KEEPS the row and the file, and reports partial', () async {
      final f = await queued();
      storage.failWith = Exception('offline');

      expect(await uploader().drain(), DrainOutcome.partial);
      final row = (await repo.pending()).single;
      expect(row.attempts, 1);
      expect(row.lastError, contains('offline'));
      expect(f.existsSync(), isTrue,
          reason: 'the local copy is the only copy until it is up');
    });

    test('a retry after the network returns uploads it', () async {
      await queued();
      storage.failWith = Exception('offline');
      await uploader().drain();

      storage.failWith = null;
      expect(await uploader().drain(), DrainOutcome.done);
      expect(await repo.pending(), isEmpty);
    });

    test('signed out, nothing is attempted at all', () async {
      await queued();
      uid = null;

      expect(await uploader().drain(), DrainOutcome.signedOut);
      expect(storage.uploaded, isEmpty);
      expect((await repo.pending()).single.attempts, 0,
          reason: 'a drain that never ran must not burn an attempt');
    });

    test('two drains at once do not upload the same object twice', () async {
      await queued();
      final u = uploader();
      final a = u.drain();
      final b = u.drain();
      final results = await Future.wait([a, b]);

      expect(results, contains(DrainOutcome.busy));
      expect(storage.uploaded.length, 1);
    });

    test('a busy drain releases, so the next one works', () async {
      await queued();
      final u = uploader();
      await Future.wait([u.drain(), u.drain()]);

      await queued(name: 'second.jpg');
      expect(await u.drain(), DrainOutcome.done);
    });
  });

  group('rows that can never succeed', () {
    test("a photo owned by ANOTHER account is dropped, not uploaded", () async {
      // Belt and braces behind the identity-change wipe. Uploading it would be
      // refused by the storage policy forever; retrying is a loop with no exit,
      // and it is not this user's photo to send.
      await queued();
      uid = 'someone-else';

      expect(await uploader().drain(), DrainOutcome.done);
      expect(storage.uploaded, isEmpty,
          reason: "one user's photo must never be uploaded as another");
      expect(await repo.pending(), isEmpty);
    });

    test('a photo whose file vanished is reaped, not retried', () async {
      final f = await queued();
      await f.delete();

      expect(await uploader().drain(), DrainOutcome.done);
      expect(storage.uploaded, isEmpty);
      expect(await repo.pending(), isEmpty,
          reason: 'a queue that cannot drain is worse than an honest loss');
    });

    test('a photo past the attempt limit is left alone by the drainer',
        () async {
      await queued();
      for (var i = 0; i < 8; i++) {
        await repo.markFailed((await repo.pending()).single, 'offline');
      }

      expect(await uploader().drain(), DrainOutcome.empty);
      expect(storage.uploaded, isEmpty,
          reason: 'giving up is the point of a limit');
      expect((await repo.stuck()).length, 1, reason: 'but it is still visible');
    });
  });

  group('urls', () {
    test('a progress photo gets a SHORT-lived signed url', () async {
      final url = await uploader()
          .urlFor(kind: PhotoKind.progress, remotePath: 'u-1/a.jpg');

      expect(url, isNotNull);
      expect(storage.signed.single, contains('ttl=${progressUrlTtl.inSeconds}'));
      expect(progressUrlTtl.inMinutes, lessThanOrEqualTo(15),
          reason: 'a signed url is a bearer token for a photo of a body');
    });

    test('a meal photo is not signed — it is read authenticated', () async {
      final url =
          await uploader().urlFor(kind: PhotoKind.meal, remotePath: 'u-1/a.jpg');

      expect(url, isNull);
      expect(storage.signed, isEmpty);
    });

    test('a failure to sign is a broken thumbnail, never a broken screen',
        () async {
      storage.failWith = Exception('nope');
      expect(
          await uploader()
              .urlFor(kind: PhotoKind.progress, remotePath: 'u-1/a.jpg'),
          isNull);
    });
  });

  test('one bad photo does not stop the ones behind it', () async {
    // The queue must keep moving. A single permanently-broken row that halted
    // the drain would strand every photo taken after it.
    final good1 = await queued(name: 'a.jpg');
    final gone = await queued(name: 'b.jpg');
    final good2 = await queued(name: 'c.jpg');
    await gone.delete();

    expect(await uploader().drain(), DrainOutcome.done);
    expect(storage.uploaded.length, 2);
    expect(await repo.pending(), isEmpty);
    expect(good1.existsSync(), isFalse);
    expect(good2.existsSync(), isFalse);
  });
}
