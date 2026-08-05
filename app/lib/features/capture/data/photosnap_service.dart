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
/// A conversational look at a photo (docs/architecture/07-photo-in-chat.md):
/// one vision call yields the coach's [answer], a reusable [description], and
/// any loggable [items].
///
/// [items] is EMPTY for a non-plated image — a menu, a packet, an ingredients
/// label — which is answered rather than refused, because that is exactly where
/// a nutrition coach earns its place. Only a plated meal is loggable.
class VisionConversation {
  const VisionConversation({
    required this.answer,
    required this.description,
    this.items = const [],
  });

  final String answer;

  /// One short line naming what is visible. Doubles as the transcript stand-in
  /// (the photo itself is never stored) AND the grounding for follow-up turns.
  final String description;

  final List<SnappedItem> items;

  bool get hasLoggableItems => items.isNotEmpty;
}

abstract class PhotoSnapService {
  /// [imageBytesBase64] is the JPEG bytes, base64-encoded (no data: prefix).
  Future<List<SnappedItem>> analyze(String imageBytesBase64, {String? byok});

  /// Converse mode: answer [question] about the photo, grounded in [context].
  Future<VisionConversation> converse(
    String imageBytesBase64, {
    String? question,
    required String context,
    String? byok,
  });
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

  @override
  Future<VisionConversation> converse(
    String imageBytesBase64, {
    String? question,
    required String context,
    String? byok,
  }) async {
    final supabase = _client ?? Supabase.instance.client;
    final FunctionResponse res;
    try {
      res = await supabase.functions.invoke(_function, body: {
        'image': imageBytesBase64,
        'mode': 'converse',
        'question': ?question,
        'context': context,
        'byok': ?byok,
      });
    } on FunctionException catch (e) {
      if (e.status == 429) {
        // Either cap can refuse; both read the same to the user.
        throw PhotoSnapException('daily limit reached', budgetExhausted: true);
      }
      throw PhotoSnapException('gateway error ${e.status}');
    } catch (e) {
      throw PhotoSnapException('network error: $e');
    }
    final data = res.data;
    final raw = data is String ? data : jsonEncode(data);
    return parseConversation(raw);
  }

  /// Parse + VALIDATE an untrusted converse response. Items go through the SAME
  /// bounds/Atwater discipline as log mode (parseItems); a missing or unusable
  /// answer is a failure, but zero items is legitimate (non-plated image).
  static VisionConversation parseConversation(String raw) {
    Map<String, dynamic> j;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) throw const FormatException('not an object');
      j = d.cast<String, dynamic>();
    } catch (_) {
      throw PhotoSnapException('malformed reply');
    }
    if (j['error'] == 'no_food') {
      // Converse mode should answer instead, but tolerate a model that refuses.
      throw PhotoSnapException('no food detected', noFood: true);
    }
    final answer = j['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw PhotoSnapException('empty answer');
    }
    final description = j['description'] is String
        ? (j['description'] as String).trim()
        : '';
    return VisionConversation(
      answer: answer.trim(),
      description: description,
      items: parseItems(raw), // same validation as the logging path
    );
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
