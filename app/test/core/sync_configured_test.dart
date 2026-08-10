import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/env/env.dart';
import 'package:sakama/core/sync/sync_service.dart';

/// Sync needs BOTH endpoints. The gate used to check only Supabase, so a build
/// with a real Supabase project and an unfilled PowerSync URL reported itself
/// configured: connect() fired, and the client retried a POST to a host that
/// does not exist every 5 seconds, indefinitely, on battery, with nothing
/// surfaced to the user.
void main() {
  const realSupabase = 'https://abc123.supabase.co';
  const realPowersync = 'https://abc123.powersync.journeyapps.com';
  const placeholderSupabase = 'https://YOUR-PROJECT.supabase.co';
  const placeholderPowersync = 'https://YOUR-INSTANCE.powersync.journeyapps.com';

  group('sync is configured only when BOTH endpoints are real', () {
    test('both real -> on', () {
      expect(Env.configuredWith(realSupabase, realPowersync), isTrue);
    });

    test('PowerSync still a placeholder -> OFF (the regression)', () {
      expect(Env.configuredWith(realSupabase, placeholderPowersync), isFalse,
          reason: 'this combination is what produced the endless retry loop');
    });

    test('Supabase still a placeholder -> off', () {
      expect(Env.configuredWith(placeholderSupabase, realPowersync), isFalse);
    });

    test('neither filled in -> off', () {
      expect(Env.configuredWith(placeholderSupabase, placeholderPowersync),
          isFalse);
    });

    test('an EMPTY value is not "configured" either', () {
      // A missing .env line yields '' rather than the placeholder, which would
      // otherwise pass a contains() check and re-open the same hole.
      expect(Env.configuredWith(realSupabase, ''), isFalse);
      expect(Env.configuredWith('', realPowersync), isFalse);
    });
  });

  test('the retry delay is well above PowerSync\'s 5s default', () {
    // Not a style preference: at the default, an unreachable instance wakes the
    // radio 720 times an hour and achieves nothing. Reconnection still needs to
    // be prompt, so this is a ceiling on waste, not a disabling of retries.
    expect(SyncService.retryDelay.inSeconds, greaterThanOrEqualTo(20));
    expect(SyncService.retryDelay.inMinutes, lessThanOrEqualTo(2),
        reason: 'still has to reconnect promptly when the server returns');
  });
}
