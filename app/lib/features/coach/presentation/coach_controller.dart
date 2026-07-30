import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../home/presentation/home_page.dart' show targetsProvider;
import '../../onboarding/domain/nutrition_targets.dart';
import '../../onboarding/domain/profile_record.dart';
import '../data/vita_service.dart';
import '../domain/coach_context.dart';
import '../domain/coach_message.dart';

/// The Vita conversation. Holds the local transcript + a sending flag. Grounds
/// every send on real data assembled fresh from the providers (PRODUCT.md:
/// the coach earns its place). Errors surface as an assistant-role message so
/// the chat stays a single readable thread.
class CoachState {
  const CoachState({this.messages = const [], this.sending = false});
  final List<CoachMessage> messages;
  final bool sending;

  CoachState copyWith({List<CoachMessage>? messages, bool? sending}) =>
      CoachState(
          messages: messages ?? this.messages,
          sending: sending ?? this.sending);
}

class CoachController extends Notifier<CoachState> {
  @override
  CoachState build() => const CoachState();

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;
    final history = [...state.messages, CoachMessage(CoachRole.user, trimmed)];
    state = state.copyWith(messages: history, sending: true);
    try {
      await ref.read(authServiceProvider).ensureSession(); // anon-first
      final byok = await ref.read(byokStoreProvider).read();
      final context = await _groundingSnapshot();
      // Only real turns go upstream — synthetic app-chrome is display-only.
      final wire = history.where((m) => !m.synthetic).toList();
      final reply = await ref
          .read(vitaServiceProvider)
          .reply(wire, context: context, byok: byok);
      state = state.copyWith(
          messages: [...history, CoachMessage(CoachRole.vita, reply)],
          sending: false);
    } on VitaException catch (e) {
      state = state.copyWith(
          messages: [
            ...history,
            CoachMessage(CoachRole.vita, _friendly(e), synthetic: true)
          ],
          sending: false);
    } catch (e) {
      debugPrint('coach send failed: $e');
      state = state.copyWith(
          messages: [
            ...history,
            const CoachMessage(CoachRole.vita,
                "I couldn't reach the network just now. Try again in a moment.",
                synthetic: true)
          ],
          sending: false);
    }
  }

  static String _friendly(VitaException e) => e.budgetExhausted
      ? "We've chatted a lot today — I reset tomorrow. Add your own AI key "
          '(Me → Your own AI key) to chat without limits.'
      : "Something went wrong reaching me. Try again in a moment.";

  Future<String> _groundingSnapshot() async {
    final ProfileRecord? profile = ref.read(profileProvider).value;
    final NutritionTargets? targets = ref.read(targetsProvider);
    final db = await ref.read(databaseProvider.future);
    final now = DateTime.now();
    final ymd = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final List<FoodLog> logs = await db.watchDay(ymd).first;
    return CoachContext.build(
        profile: profile, targets: targets, todayLogs: logs, now: now);
  }
}

final coachControllerProvider =
    NotifierProvider<CoachController, CoachState>(CoachController.new);
