import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'memory_repository.dart';

/// One thing Vita learned, before it is stored.
class ExtractedFact {
  const ExtractedFact(this.kind, this.content, this.confidence);
  final String kind;
  final String content;
  final double confidence;
}

/// What an extraction pass produced: durable facts plus a refreshed summary.
class Extraction {
  const Extraction({this.facts = const [], this.summary});
  final List<ExtractedFact> facts;
  final String? summary;

  bool get isEmpty => facts.isEmpty && (summary == null || summary!.isEmpty);
}

/// Distils a transcript into facts worth remembering (ADR 0016 decision 5).
///
/// AN INTERFACE ON PURPOSE. Extraction is exactly the workload Apple's
/// Foundation Models framework is built for — classification and structured
/// output, on-device, free, with no app-size cost — and moving it there would
/// upgrade ADR 0016's promise from "memory is device-local at rest" to
/// "device-local, full stop", because the transcript would stop leaving the
/// phone to be distilled. That needs a spike on real hardware before we commit,
/// so today's implementation is the Edge Function; the seam is what makes the
/// on-device version a drop-in rather than a rewrite.
abstract class MemoryExtractor {
  Future<Extraction> extract({
    required List<({String role, String content})> turns,
    String? priorSummary,
    String? byok,
  });
}

class EdgeFunctionMemoryExtractor implements MemoryExtractor {
  EdgeFunctionMemoryExtractor({SupabaseClient? client})
      : _client = client; // ignore: prefer_initializing_formals
  final SupabaseClient? _client;

  @override
  Future<Extraction> extract({
    required List<({String role, String content})> turns,
    String? priorSummary,
    String? byok,
  }) async {
    if (turns.isEmpty) return const Extraction();
    final supabase = _client ?? Supabase.instance.client;
    final res = await supabase.functions.invoke('vita', body: {
      'mode': 'extract',
      'turns': [
        for (final t in turns) {'role': t.role, 'content': t.content}
      ],
      'prior_summary': ?priorSummary,
      'byok': ?byok,
    });
    final data = res.data;
    return parse(data is String ? data : jsonEncode(data));
  }

  /// Parse UNTRUSTED model output. Every field is validated, and anything
  /// unusable is dropped rather than stored: a junk memory is worse than a
  /// missing one, because the user sees it, cannot edit it (decision 10), and
  /// it silently steers future replies.
  @visibleForTesting
  static Extraction parse(String raw) {
    Map<String, dynamic> j;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return const Extraction();
      j = d.cast<String, dynamic>();
    } catch (_) {
      return const Extraction();
    }

    final facts = <ExtractedFact>[];
    final list = j['facts'];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final kind = item['kind'];
        final content = item['content'];
        if (kind is! String || !MemoryRepository.isValidKind(kind)) continue;
        if (content is! String) continue;
        final text = content.trim();
        // A one-word "fact" carries no meaning once its thread is gone, and an
        // essay is a summary wearing a fact's clothes.
        if (text.length < 4 || text.length > 200) continue;
        facts.add(ExtractedFact(kind, text, _confidence(item['confidence'])));
      }
    }

    final summary = j['summary'];
    return Extraction(
      // A runaway list would flood the memory page and the prompt alike.
      facts: facts.take(10).toList(),
      summary: summary is String && summary.trim().isNotEmpty
          ? summary.trim().substring(0, summary.trim().length.clamp(0, 600))
          : null,
    );
  }

  /// Non-finite values must be rejected at coercion, not by a range check:
  /// every comparison against NaN is false, so a NaN would pass both bounds
  /// and land in the ranking as a confidence. Same trap as the tool-call
  /// parser, same fix.
  static double _confidence(Object? v) {
    final d = switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    if (d == null || !d.isFinite) return 0.5;
    return d.clamp(0.0, 1.0);
  }
}
