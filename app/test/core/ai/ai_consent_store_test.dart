import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/ai/ai_consent_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('never-asked reads as null (tri-state)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AiConsentStore().read(), isNull);
  });

  test('write true then read true', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AiConsentStore();
    await s.write(true);
    expect(await s.read(), isTrue);
  });

  test('write false is distinct from never-asked', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AiConsentStore();
    await s.write(false);
    // Explicitly off must NOT read as null — else the first-use gate would
    // re-appear for a user who deliberately turned AI off.
    expect(await s.read(), isFalse);
  });

  test('persists across store instances (same prefs backing)', () async {
    SharedPreferences.setMockInitialValues({});
    await AiConsentStore().write(true);
    expect(await AiConsentStore().read(), isTrue);
  });
}
