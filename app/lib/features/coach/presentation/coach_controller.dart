import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../home/presentation/home_page.dart' show targetsProvider;
import '../../onboarding/domain/nutrition_targets.dart';
import '../../onboarding/domain/profile_record.dart';
import '../../plans/application/plan_providers.dart';
import '../data/vita_service.dart';
import '../domain/coach_context.dart';
import '../domain/coach_message.dart';

/// The Vita conversation, now backed by the device-local chat tables (ADR 0016
/// phase 1) rather than living only in memory — the transcript survives a
/// restart. Grounds every send on real data assembled fresh from the providers
/// (PRODUCT.md: the coach earns its place). Errors surface as an assistant-role
/// message so the chat stays a single readable thread.
class CoachState {
  const CoachState({
    this.threadId,
    this.messages = const [],
    this.sending = false,
    this.loading = true,
  });

  /// The thread being displayed. Null until the first message creates one.
  final String? threadId;
  final List<CoachMessage> messages;
  final bool sending;

  /// True while the stored transcript is being restored.
  final bool loading;

  CoachState copyWith({
    String? threadId,
    List<CoachMessage>? messages,
    bool? sending,
    bool? loading,
  }) =>
      CoachState(
        threadId: threadId ?? this.threadId,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        loading: loading ?? this.loading,
      );
}

class CoachController extends Notifier<CoachState> {
  /// How many prior turns are replayed upstream. Threading exists partly so
  /// this stays bounded — an ever-growing transcript would make every turn more
  /// expensive than the last (CLAUDE.md rule 9). A constant, not a contract.
  static const historyWindow = 20;

  @override
  CoachState build() {
    unawaited(_restore());
    return const CoachState();
  }

  /// Write state only if this provider is still alive. Every path here crosses
  /// an async gap (db + network), and the user can leave the Coach tab —
  /// disposing the provider — while that work is in flight.
  void _set(CoachState next) {
    if (ref.mounted) state = next;
  }

  /// Restore the most recent thread on open.
  Future<void> _restore() async {
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final uid = ref.read(currentUserIdProvider);
      // Pre-auth threads are born with a null user_id and no server ever
      // backfills a local-only row, so adopt them once a session exists —
      // otherwise they strand invisible forever (review #83).
      if (uid != null) await repo.adoptOrphanThreads(uid);
      final thread = await repo.latestThread(uid);
      if (thread == null) {
        _set(state.copyWith(loading: false));
        return;
      }
      final rows = await repo.messagesOf(thread.id);
      _set(CoachState(
        threadId: thread.id,
        messages: rows.map(_toMessage).toList(),
        loading: false,
      ));
    } catch (e) {
      debugPrint('coach restore failed: $e');
      if (ref.mounted) _set(state.copyWith(loading: false)); // empty chat still works
    }
  }

  static CoachMessage _toMessage(ChatMessageRow r) => CoachMessage(
        r.role == 'user' ? CoachRole.user : CoachRole.vita,
        r.content,
        synthetic: r.synthetic,
      );

  /// Start a fresh conversation. The current one stays saved.
  void newThread() =>
      state = const CoachState(loading: false); // threadId null → created on send

  /// Switch to a saved conversation. Guarded like [_restore] — the provider can
  /// be disposed mid-await if the user leaves the tab (review #85 nit).
  Future<void> openThread(String threadId) async {
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final rows = await repo.messagesOf(threadId);
      _set(CoachState(
        threadId: threadId,
        messages: rows.map(_toMessage).toList(),
        loading: false,
      ));
    } catch (e) {
      debugPrint('coach openThread failed: $e');
    }
  }

  Future<void> deleteThread(String threadId) async {
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      await repo.deleteThread(threadId);
      if (ref.mounted && state.threadId == threadId) {
        await _restore(); // fall back to the next saved conversation
      }
    } catch (e) {
      debugPrint('coach deleteThread failed: $e');
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;

    final repo = await ref.read(chatRepositoryProvider.future);
    // Persist the user's turn FIRST, so a crash or a failed reply can never
    // lose what they typed.
    final threadId = state.threadId ??
        await repo.createThread(
            title: trimmed, userId: ref.read(currentUserIdProvider));
    await repo.appendMessage(
        threadId: threadId, role: 'user', content: trimmed);

    final history = [...state.messages, CoachMessage(CoachRole.user, trimmed)];
    _set(state.copyWith(
        threadId: threadId, messages: history, sending: true, loading: false));

    Future<void> persistReply(String content, {bool synthetic = false}) async {
      await repo.appendMessage(
          threadId: threadId,
          role: 'vita',
          content: content,
          synthetic: synthetic);
      _set(state.copyWith(
        messages: [
          ...history,
          CoachMessage(CoachRole.vita, content, synthetic: synthetic)
        ],
        sending: false,
      ));
    }

    try {
      await ref.read(authServiceProvider).ensureSession(); // anon-first
      final byok = await ref.read(byokStoreProvider).read();
      final context = await _groundingSnapshot();
      // Only real turns go upstream — synthetic app-chrome is display-only —
      // and only the last [historyWindow] of them, so cost stays bounded.
      final real = history.where((m) => !m.synthetic).toList();
      final wire = real.length <= historyWindow
          ? real
          : real.sublist(real.length - historyWindow);
      final reply = await ref
          .read(vitaServiceProvider)
          .reply(wire, context: context, byok: byok);
      await persistReply(reply);
    } on VitaException catch (e) {
      await persistReply(_friendly(e), synthetic: true);
    } catch (e) {
      debugPrint('coach send failed: $e');
      await persistReply(
          "I couldn't reach the network just now. Try again in a moment.",
          synthetic: true);
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
    final planDay = ref.read(activePlanDayProvider);
    return CoachContext.build(
        profile: profile,
        targets: targets,
        todayLogs: logs,
        now: now,
        planDay: planDay);
  }
}

final coachControllerProvider =
    NotifierProvider<CoachController, CoachState>(CoachController.new);

/// Saved conversations for the current user, most recent first.
final chatThreadsProvider = StreamProvider<List<ChatThreadRow>>((ref) async* {
  final repo = await ref.watch(chatRepositoryProvider.future);
  yield* repo.watchThreads(ref.watch(currentUserIdProvider));
});
