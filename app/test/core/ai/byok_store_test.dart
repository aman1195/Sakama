import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/ai/byok_store.dart';

/// In-memory fake so the store is testable without the platform keychain.
class _MemStorage extends Fake implements FlutterSecureStorage {
  final _m = <String, String>{};
  @override
  Future<String?> read({required String key, /*ignore rest*/
      dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions,
      dynamic mOptions, dynamic wOptions}) async => _m[key];
  @override
  Future<void> write({required String key, required String? value,
      dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions,
      dynamic mOptions, dynamic wOptions}) async {
    if (value == null) { _m.remove(key); } else { _m[key] = value; }
  }
  @override
  Future<void> delete({required String key,
      dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions,
      dynamic mOptions, dynamic wOptions}) async => _m.remove(key);
}

void main() {
  test('looksValid: sk- prefix and length', () {
    expect(ByokStore.looksValid('sk-or-v1-abcdefghijklmnop'), isTrue);
    expect(ByokStore.looksValid('nope'), isFalse);
    expect(ByokStore.looksValid('sk-short'), isFalse);
    expect(ByokStore.looksValid('  sk-or-v1-abcdefghijklmnop  '), isTrue);
  });

  test('save / read / has / clear round-trip; trims whitespace', () async {
    final s = ByokStore(storage: _MemStorage());
    expect(await s.has(), isFalse);
    await s.save('  sk-or-v1-longkeyvalue123456  ');
    expect(await s.read(), 'sk-or-v1-longkeyvalue123456');
    expect(await s.has(), isTrue);
    await s.clear();
    expect(await s.read(), isNull);
    expect(await s.has(), isFalse);
  });

  test('empty stored value reads as null (absent, not "")', () async {
    final mem = _MemStorage();
    final s = ByokStore(storage: mem);
    await mem.write(key: 'openrouter_byok', value: '');
    expect(await s.read(), isNull);
  });
}
