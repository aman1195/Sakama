import 'package:sakama/core/ai/byok_store.dart';

/// In-memory [ByokStore] for tests. The real store reaches the platform secure
/// enclave over a MethodChannel, which has no handler under `flutter_test` and
/// hangs; this fake keeps unit tests off the channel entirely. Defaults to "no
/// key" so the metered path is exercised.
class FakeByokStore implements ByokStore {
  FakeByokStore([this._key]);
  String? _key;

  @override
  Future<String?> read() async => _key;

  @override
  Future<bool> has() async => _key != null;

  @override
  Future<void> save(String key) async => _key = key.trim();

  @override
  Future<void> clear() async => _key = null;
}
