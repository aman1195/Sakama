import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/config/remote_config.dart';

void main() {
  group('RemoteConfig.fromRows', () {
    test('parses min build and flags; ignores unknown keys', () {
      final c = RemoteConfig.fromRows([
        {'key': 'min_supported_build', 'value': '7'},
        {'key': 'flag.photosnap', 'value': 'true'},
        {'key': 'flag.voice', 'value': 'FALSE'},
        {'key': 'some_other_key', 'value': 'ignored'},
      ]);
      expect(c.minSupportedBuild, 7);
      expect(c.flag('photosnap'), isTrue);
      expect(c.flag('voice'), isFalse);
    });

    test('defaults: no floor and flags fall back to orElse', () {
      const c = RemoteConfig();
      expect(c.minSupportedBuild, 0);
      expect(c.flag('anything', orElse: true), isTrue);
      expect(c.flag('anything', orElse: false), isFalse);
    });

    test('garbage min build parses to 0 (no floor), never throws', () {
      final c = RemoteConfig.fromRows([
        {'key': 'min_supported_build', 'value': 'not-a-number'},
      ]);
      expect(c.minSupportedBuild, 0);
    });

    test('whitespace and mixed case flag values are handled', () {
      final c = RemoteConfig.fromRows([
        {'key': 'flag.x', 'value': '  True  '},
      ]);
      expect(c.flag('x'), isTrue);
    });
  });
}
