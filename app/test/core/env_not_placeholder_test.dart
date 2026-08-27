import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/env/env.dart';

/// A build must never ship placeholder credentials silently.
///
/// This cost days. `.env` was swapped to `.env.example` to verify tests under
/// CI conditions, restored, and regenerated — but **build_runner caches the
/// .env contents**, and `--delete-conflicting-outputs` does not clear that
/// cache. Only `dart run build_runner clean` does. So `env.g.dart` kept the
/// placeholder values while `.env` held the real ones, and every build after
/// that point compiled `https://YOUR-PROJECT.supabase.co` into the app.
///
/// The symptoms looked like three unrelated problems: sync never reaching the
/// server, Vita reporting "couldn't reach the network", and a device that
/// seemed to have DNS trouble. One cause.
///
/// SKIPPED IN CI, which genuinely has no .env — the point is to catch a
/// DEVELOPER build that is about to be installed on a phone.
void main() {
  test('a configured checkout does not compile placeholders', () {
    if (!Env.isConfigured) {
      // CI, or a fresh clone before `cp .env.example .env`. Nothing to check:
      // an unconfigured build is a legitimate local-only build.
      return;
    }
    // If isConfigured is true, the values must be REAL — the failure mode was
    // a build that believed it was configured while holding placeholders.
    expect(Env.supabaseUrl, isNot(contains('YOUR-PROJECT')));
    expect(Env.powersyncUrl, isNot(contains('YOUR-INSTANCE')));
    expect(Env.supabaseAnonKey.length, greaterThan(40),
        reason: 'a real anon key is a JWT, not a placeholder string');
  });

  test('the guard itself rejects placeholders', () {
    // configuredWith is the source of truth; assert it directly so this file
    // still means something in CI where the values above are absent.
    expect(
        Env.configuredWith(
            'https://YOUR-PROJECT.supabase.co', 'https://real.powersync.com'),
        isFalse);
    expect(
        Env.configuredWith('https://real.supabase.co',
            'https://YOUR-INSTANCE.powersync.journeyapps.com'),
        isFalse);
  });
}
