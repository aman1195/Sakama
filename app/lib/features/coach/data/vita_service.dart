import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach_message.dart';

class VitaException implements Exception {
  VitaException(this.message, {this.budgetExhausted = false});
  final String message;
  final bool budgetExhausted;
  @override
  String toString() => 'VitaException: $message';
}

/// Sends the conversation + grounding snapshot to the Vita Edge Function.
/// Injectable so the chat UI + tests never touch the network.
abstract class VitaService {
  Future<String> reply(List<CoachMessage> history, {required String context, String? byok});
}

class EdgeFunctionVita implements VitaService {
  EdgeFunctionVita({SupabaseClient? client})
      : _client = client; // ignore: prefer_initializing_formals
  final SupabaseClient? _client;
  static const _function = 'vita';

  @override
  Future<String> reply(List<CoachMessage> history,
      {required String context, String? byok}) async {
    final supabase = _client ?? Supabase.instance.client;
    final FunctionResponse res;
    try {
      res = await supabase.functions.invoke(_function, body: {
        'messages': history.map((m) => m.toWire()).toList(),
        'context': context,
        'byok': ?byok,
      });
    } on FunctionException catch (e) {
      if (e.status == 429) {
        throw VitaException('daily coach limit reached', budgetExhausted: true);
      }
      throw VitaException('gateway error ${e.status}');
    } catch (e) {
      throw VitaException('network error: $e');
    }
    final data = res.data;
    final reply = data is Map ? data['reply'] : null;
    if (reply is! String || reply.trim().isEmpty) {
      throw VitaException('empty reply');
    }
    return reply.trim();
  }
}
