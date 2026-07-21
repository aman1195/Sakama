/// Server-controlled app config: the min-version gate + feature kill-switches.
/// NOT per-user data and NOT synced via PowerSync — it's global config fetched
/// from a public, read-only Supabase table (see supabase/migrations app_config).
class RemoteConfig {
  const RemoteConfig({
    this.minSupportedBuild = 0,
    this.flags = const {},
  });

  /// The lowest build number allowed to run. A client below this must update.
  /// 0 means "no floor" (the safe default when config is unknown).
  final int minSupportedBuild;

  /// Feature kill-switches, e.g. {'photosnap': true}. Absent => default in code.
  final Map<String, bool> flags;

  bool flag(String name, {bool orElse = true}) => flags[name] ?? orElse;

  /// Parse the key/value rows from the app_config table.
  /// Rows: {key: 'min_supported_build', value: '3'} and
  ///       {key: 'flag.photosnap', value: 'true'}.
  factory RemoteConfig.fromRows(List<Map<String, dynamic>> rows) {
    var minBuild = 0;
    final flags = <String, bool>{};
    for (final r in rows) {
      final key = r['key'] as String?;
      final value = (r['value'] ?? '').toString().trim();
      if (key == null) continue;
      if (key == 'min_supported_build') {
        minBuild = int.tryParse(value) ?? 0;
      } else if (key.startsWith('flag.')) {
        flags[key.substring(5)] = value.toLowerCase() == 'true';
      }
    }
    return RemoteConfig(minSupportedBuild: minBuild, flags: flags);
  }
}
