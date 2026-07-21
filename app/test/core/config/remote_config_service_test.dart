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

    test('unparseable build number reads as 0 => blocks against any floor',
        () async {
      final svc = RemoteConfigService(packageInfo: _infoWithBuild('nonsense'));
      // A build we cannot read is treated as ancient — safest against a floor.
      expect(await svc.mustUpdate(const RemoteConfig(minSupportedBuild: 2)),
          isTrue);
    });
  });
}
