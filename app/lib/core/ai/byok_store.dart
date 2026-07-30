import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bring-Your-Own-Key storage (M3.4, ADR 0011). The user's own OpenRouter key
/// lives ONLY in the platform secure enclave (Keychain / EncryptedSharedPrefs)
/// on THIS device — we never persist it server-side, never log it, and it is
/// sent to our Edge Function only to be forwarded upstream (the function uses
/// it in place of our key and skips the free-tier cap). Minimises our custody
/// of a user secret to zero at rest on our infra.
class ByokStore {
  ByokStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  static const _key = 'openrouter_byok';

  /// A plausible OpenRouter key. Cheap client guard before we bother the
  /// gateway; the real check is whether the provider accepts it.
  static bool looksValid(String key) =>
      key.trim().startsWith('sk-') && key.trim().length > 20;

  Future<String?> read() async {
    // Defensive: a BYOK key is an optional enhancement, never a hard
    // dependency. If the secure enclave is unavailable (locked keychain,
    // first-run plugin channel not ready, unsupported platform) treat it as
    // "no key" and fall back to the metered gateway rather than failing the
    // whole AI call.
    try {
      final v = await _storage.read(key: _key);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<bool> has() async => (await read()) != null;

  Future<void> save(String key) async =>
      _storage.write(key: _key, value: key.trim());

  Future<void> clear() async => _storage.delete(key: _key);
}
