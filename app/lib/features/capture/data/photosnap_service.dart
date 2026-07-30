import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/snapped_item.dart';

class PhotoSnapException implements Exception {
  PhotoSnapException(this.message,
      {this.budgetExhausted = false, this.noFood = false});
  final String message;
  final bool budgetExhausted; // daily cap hit (rule 9)
  final bool noFood;          // model saw no food in the frame
  @override
  String toString() => 'PhotoSnapException: $message';
}

/// Sends a meal photo to the PhotoSnap Edge Function and returns validated
/// items. Injectable so the UI + tests never touch the network.
abstract class PhotoSnapService {
  /// [imageBytesBase64] is the JPEG bytes, base64-encoded (no data: prefix).
  Future<List<SnappedItem>> analyze(String imageBytesBase64, {String? byok});
}

class EdgeFunctionPhotoSnap implements PhotoSnapService {
  EdgeFunctionPhotoSnap({SupabaseClient? client})
      : _client = client; // ignore: prefer_initializing_formals
  final SupabaseClient? _client;

  static const _function = 'photosnap';

  @override
  Future<List<SnappedItem>> analyze(String imageBytesBase64, {String? byok}) async {
    final supabase = _client ?? Supabase.instance.client;
    final FunctionResponse res;
    try {
      res = await supabase.functions
          .invoke(_function, body: {'image': imageBytesBase64, 'byok': ?byok});
    } on FunctionException catch (e) {
      if (e.status == 429) {
        throw PhotoSnapException('daily photo limit reached',
            budgetExhausted: true);
      }
      throw PhotoSnapException('gateway error ${e.status}');
    } catch (e) {
      throw PhotoSnapException('network error: $e');
    }
    final data = res.data;
    final raw = data is String ? data : jsonEncode(data);
    if (_isNoFood(raw)) {
      throw PhotoSnapException('no food detected', noFood: true);
    }
    final items = parseItems(raw);
    if (items.isEmpty) throw PhotoSnapException('nothing usable in the photo');
    return items;
  }

  static bool _isNoFood(String raw) {
    try {
      final j = jsonDecode(raw);
      return j is Map && j['error'] == 'no_food';
    } catch (_) {
      return false;
    }
  }

  /// Parse + VALIDATE the model's items. Untrusted input: each item is
  /// bounds-checked and Atwater-cross-checked independently; bad items are
  /// DROPPED (not defaulted), so a single hallucinated row can't poison a log.
  static List<SnappedItem> parseItems(String raw) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const [];
    }
    final list = j['items'];
    if (list is! List) return const [];

    double? n(Object? v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

    final out = <SnappedItem>[];
    for (final entry in list.take(8)) {
      if (entry is! Map) continue;
      final name = (entry['name'] as String?)?.trim();
      final kcal = n(entry['energy_kcal']);
      final protein = n(entry['protein_g']);
      final carb = n(entry['carb_g']);
      final fat = n(entry['fat_g']);
      final grams = n(entry['grams']);
      if (name == null || name.isEmpty) continue;
      if (kcal == null || protein == null || carb == null || fat == null) {
        continue;
      }
      // Per-portion sanity: 5..2000 kcal, macros 0..300g, grams 1..2000.
      if (kcal < 5 || kcal > 2000) continue;
      if ([protein, carb, fat].any((m) => m < 0 || m > 300)) continue;
      if (grams != null && (grams < 1 || grams > 2000)) continue;
      // Atwater cross-check on the portion (±45% — looser than text estimate
      // since portion grams add a second source of slack).
      final atwater = protein * 4 + carb * 4 + fat * 9;
      if (atwater > 0 && (kcal - atwater).abs() / atwater > 0.45) continue;

      final rawConf = n(entry['confidence']) ?? 0.4;
      out.add(SnappedItem(
        name: name,
        portionLabel: (entry['portion_label'] as String?)?.trim() ?? '1 serving',
        grams: grams, // nullable — confirm sheet asks when absent
        energyKcal: kcal,
        proteinG: protein,
        carbG: carb,
        fatG: fat,
        confidence: rawConf.clamp(0.2, 0.49).toDouble(),
      ));
    }
    return out;
  }
}
