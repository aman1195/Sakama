import 'dart:convert';

import 'package:http/http.dart' as http;

/// A product resolved from Open Food Facts. Drift-free so parsing is testable
/// without a database. Nutrition is per 100 g (OFF's `*_100g` fields), matching
/// our canonical basis (CLAUDE.md).
class OffProduct {
  const OffProduct({
    required this.barcode,
    required this.name,
    this.brands,
    required this.energyKcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    this.fiberG,
    this.servingLabel,
    this.servingGrams,
  });

  final String barcode;
  final String name;
  final String? brands;
  final double energyKcal, proteinG, carbG, fatG;
  final double? fiberG;
  final String? servingLabel;
  final double? servingGrams;

  /// Display name including the brand, which is what a scanned pack shows.
  String get displayName =>
      (brands == null || brands!.isEmpty) ? name : '$name ($brands)';
}

/// Raised for a genuine lookup failure (network/server), as distinct from a
/// well-formed "product not found" — the caller treats those differently.
class OffLookupException implements Exception {
  OffLookupException(this.message);
  final String message;
  @override
  String toString() => 'OffLookupException: $message';
}

/// Read-only Open Food Facts API client.
///
/// LIVE LOOKUP ONLY — we do NOT ship an OFF-derived snapshot. Individually
/// requested lookups are a far weaker "derivative database" claim than a
/// bundled export, which keeps ODbL share-alike exposure low (ASSET_CREDITS.md
/// Option A). Results are cached locally per scanned barcode by OffRepository;
/// logged foods copy their values into food_logs, so the diary still renders
/// offline forever without any OFF row present.
class OffClient {
  OffClient({http.Client? httpClient, this.appVersion = '1.0.0'})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String appVersion;

  static const _host = 'world.openfoodfacts.org';
  static const _timeout = Duration(seconds: 8);

  /// OFF REQUIRES an identifying User-Agent (anonymous clients get blocked)
  /// and asks for app name, version and a contact.
  Map<String, String> get _headers => {
        'User-Agent': 'Sakama/$appVersion (contact@sakama.app)',
        'Accept': 'application/json',
      };

  /// Only the fields we actually store — smaller payloads, less bandwidth on
  /// Indian mobile data, and no incidental collection of data we do not use.
  static const _fields =
      'code,product_name,brands,serving_size,nutriments';

  /// Returns the product, or null when OFF has no record of [barcode].
  /// Throws [OffLookupException] on network/server failure.
  Future<OffProduct?> fetch(String barcode) async {
    final uri = Uri.https(_host, '/api/v2/product/$barcode.json',
        {'fields': _fields});
    final http.Response res;
    try {
      res = await _http.get(uri, headers: _headers).timeout(_timeout);
    } catch (e) {
      throw OffLookupException('network error: $e');
    }
    if (res.statusCode == 404) return null; // v2 uses 404 for unknown codes
    if (res.statusCode != 200) {
      throw OffLookupException('HTTP ${res.statusCode}');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw OffLookupException('malformed response');
    }
    // v2 still reports a miss in-band on some deployments.
    if (body['status'] == 0) return null;
    final product = body['product'];
    if (product is! Map<String, dynamic>) return null;

    return parseProduct(barcode, product);
  }

  /// Exposed for tests: map an OFF `product` object to [OffProduct].
  /// Returns null when the record lacks a usable name or energy value — a
  /// nameless or calorie-less row is not worth showing in a food diary.
  static OffProduct? parseProduct(String barcode, Map<String, dynamic> p) {
    final name = (p['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;

    final n = (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? const {};
    final kcal = _num(n['energy-kcal_100g']);
    if (kcal == null || kcal <= 0) return null;

    final serving = (p['serving_size'] as String?)?.trim();
    return OffProduct(
      barcode: barcode,
      name: name,
      brands: (p['brands'] as String?)?.trim(),
      energyKcal: kcal,
      proteinG: _num(n['proteins_100g']) ?? 0,
      carbG: _num(n['carbohydrates_100g']) ?? 0,
      fatG: _num(n['fat_100g']) ?? 0,
      fiberG: _num(n['fiber_100g']),
      servingLabel: (serving == null || serving.isEmpty) ? null : serving,
      servingGrams: _gramsFrom(serving),
    );
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// "30 g" / "30g" / "1 bar (30 g)" -> 30. Null when no gram figure is present
  /// (e.g. "1 cup"), in which case the UI falls back to a manual amount.
  static double? _gramsFrom(String? serving) {
    if (serving == null) return null;
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*g\b', caseSensitive: false)
        .firstMatch(serving);
    return m == null ? null : double.tryParse(m.group(1)!);
  }
}
