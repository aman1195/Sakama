import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sakama/core/config/remote_config.dart';
import 'package:sakama/core/config/remote_config_service.dart';

PackageInfo _infoWithBuild(String build) => PackageInfo(
      appName: 'Sakama',
      packageName: 'ai.sakama.app',
      version: '1.0.0',
      buildNumber: build,
    );

void main() {
  group('mustUpdate — the gate decision', () {
    test('no floor known => never blocks (fail-open)', () async {
      final svc = RemoteConfigService(packageInfo: _infoWithBuild('1'));
      expect(await svc.mustUpdate(const RemoteConfig(minSupportedBuild: 0)),
          isFalse);
    });

    test('running build below floor => blocks', () async {
      final svc = RemoteConfigService(packageInfo: _infoWithBuild('3'));
      expect(await svc.mustUpdate(const RemoteConfig(minSupportedBuild: 5)),
          isTrue);
    });

    test('running build at or above floor => allowed', () async {
      final svc = RemoteConfigService(packageInfo: _infoWithBuild('5'));
      expect(await svc.mustUpdate(const RemoteConfig(minSupportedBuild: 5)),
          isFalse);
      final svc2 = RemoteConfigService(packageInfo: _infoWithBuild('9'));
      expect(await svc2.mustUpdate(const RemoteConfig(minSupportedBuild: 5)),
          isFalse);
    });

    test('unidentifiable build => fail-open (allowed), never bricks the user',
        () async {
      // iOS CFBundleVersion may be dot-separated ("1.2.3"), which does not
      // parse to an int. A build we cannot identify must NOT be pulled — you
      // cannot safely force-update off a version you can't even read. This is
      // the whole point of the gate: it must never brick a working user.
      final dotted = RemoteConfigService(packageInfo: _infoWithBuild('1.2.3'));
      expect(await dotted.mustUpdate(const RemoteConfig(minSupportedBuild: 2)),
          isFalse);
      final garbage =
          RemoteConfigService(packageInfo: _infoWithBuild('nonsense'));
      expect(await garbage.mustUpdate(const RemoteConfig(minSupportedBuild: 9)),
          isFalse);
    });
  });
}
