import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/me/presentation/sync_failure_notice.dart';

/// The notice appears only when something was actually lost, and says so in a
/// sentence a person would write.
void main() {
  test('says nothing when nothing was lost', () {
    expect(SyncFailureNotice.title(0), isNull,
        reason: 'a permanent "sync is fine" row would just be noise');
    expect(SyncFailureNotice.title(-1), isNull);
  });

  test('singular for one — "1 entries" is a tell that nobody read the screen',
      () {
    expect(SyncFailureNotice.title(1), "1 entry didn't save");
  });

  test('counts the rest', () {
    expect(SyncFailureNotice.title(2), "2 entries didn't save");
    expect(SyncFailureNotice.title(17), "17 entries didn't save");
  });
}
