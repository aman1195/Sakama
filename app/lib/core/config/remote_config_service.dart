import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env/env.dart';
import 'remote_config.dart';

/// Fetches [RemoteConfig] from the public app_config table and decides whether
/// the running build must update.
///
/// OFFLINE-FIRST + FAIL-OPEN (CLAUDE.md rule 1): the gate must never lock out a
/// user who is merely offline. It blocks ONLY when a KNOWN min-build (fetched
/// now, or cached from a prior successful fetch) exceeds the running build. If
/// config was never obtained, it allows. The last-known min-build is cached so
/// a subsequent offline launch still enforces a floor we already learned.
class RemoteConfigService {
  RemoteConfigService({PackageInfo? packageInfo}) : _injectedInfo = packageInfo;

  final PackageInfo? _injectedInfo;
  static const _cachedMinBuildKey = 'remote_config.min_build';

  Future<int> currentBuild() async {
    final info = _injectedInfo ?? await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// Fetch config. On any failure, fall back to a cached min-build (so an
  /// offline client still honours a floor it learned earlier).
  Future<RemoteConfig> fetch() async {
    if (!Env.isConfigured) return const RemoteConfig();
    try {
      final rows = await Supabase.instance.client
          .from('app_config')
          .select('key,value')
          .timeout(const Duration(seconds: 5));
      final config = RemoteConfig.fromRows(
          (rows as List).cast<Map<String, dynamic>>());
      // Persist the learned floor for offline enforcement.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cachedMinBuildKey, config.minSupportedBuild);
      return config;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getInt(_cachedMinBuildKey) ?? 0;
      return RemoteConfig(minSupportedBuild: cached);
    }
  }

  /// True only when we KNOW the running build is below the required floor.
  Future<bool> mustUpdate(RemoteConfig config) async {
    if (config.minSupportedBuild <= 0) return false; // no floor known -> allow
    return (await currentBuild()) < config.minSupportedBuild;
  }

  /// Convenience wrapper for cheap JSON round-tripping in tests.
  static RemoteConfig configFromJson(String s) =>
      RemoteConfig.fromRows((jsonDecode(s) as List).cast<Map<String, dynamic>>());
}
