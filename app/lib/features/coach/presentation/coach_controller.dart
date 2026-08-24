import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../home/presentation/home_page.dart' show targetsProvider;
import '../../onboarding/domain/nutrition_targets.dart';
import '../../onboarding/domain/profile_record.dart';
import '../../home/domain/day_totals.dart' show Meal;
import '../../plans/application/plan_providers.dart';
import '../../capture/data/photosnap_service.dart';
import '../../capture/domain/snapped_item.dart';
import '../data/tool_executor.dart';
import '../data/vita_service.dart';
import '../domain/coach_context.dart';
import '../domain/coach_message.dart';
import '../domain/tool_draft.dart';

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
    this.pendingDrafts = const [],
    this.carriedItems = const [],
  });

  /// The thread being displayed. Null until the first message creates one.
  final String? threadId;
  final List<CoachMessage> messages;
  final bool sending;

  /// True while the stored transcript is being restored.
  final bool loading;

  /// Items handed over from a PhotoSnap result, kept so that a later "I just
  /// ate this" proposes the WHOLE meal with its real macros — instead of the
  /// single-food tool call re-deriving one item from the text summary.
  final List<SnappedItem> carriedItems;

  /// Actions Vita has PROPOSED, awaiting the user's confirmation. A LIST because
  /// one photo of a thali is five foods, not one. Deliberately NOT persisted: a
  /// stale proposal should not survive a restart and reappear as if still live.
  final List<ToolDraft> pendingDrafts;

  /// Convenience for the single-draft (text tool-call) case.
  ToolDraft? get pendingDraft =>
      pendingDrafts.isEmpty ? null : pendingDrafts.first;

  CoachState copyWith({
    String? threadId,
    List<CoachMessage>? messages,
    bool? sending,
    bool? loading,
    List<ToolDraft>? pendingDrafts,
    List<SnappedItem>? carriedItems,
    bool clearDraft = false,
  }) =>
      CoachState(
        threadId: threadId ?? this.threadId,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        loading: loading ?? this.loading,
        pendingDrafts:
            clearDraft ? const [] : (pendingDrafts ?? this.pendingDrafts),
        carriedItems: carriedItems ?? this.carriedItems,
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

  /// Restore the most recent thread.
  ///
  /// [force] distinguishes the two callers, which want opposite things: the
  /// build-time restore must NOT clobber whatever happened while it was in
  /// flight, whereas the post-delete fallback must replace the state showing
  /// the thread that no longer exists.
  Future<void> _restore({bool force = false}) async {
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final uid = ref.read(currentUserIdProvider);
      // Pre-auth threads are born with a null user_id and no server ever
      // backfills a local-only row, so adopt them once a session exists —
      // otherwise they strand invisible forever (review #83).
      if (uid != null) {
        await repo.adoptOrphanThreads(uid);
        // Facts learned before the first sign-in strand the same way threads
        // do, and a stranded memory is worse: the user sees Vita forget them
        // for no visible reason.
        final memory = await ref.read(memoryRepositoryProvider.future);
        await memory.adoptOrphans(uid);
      }
      final thread = await repo.latestThread(uid);
      if (thread == null) {
        _set(force
            ? const CoachState(loading: false) // the last thread was deleted
            : state.copyWith(loading: false));
        return;
      }
      final rows = await repo.messagesOf(thread.id);
      // Restore is fire-and-forget from build(), so the user (or a PhotoSnap
      // handoff) can act BEFORE it finishes. Writing a fresh CoachState here
      // would clobber that — silently dropping carried items, or a message
      // sent the instant Coach opened. Whoever got there first wins.
      if (!force &&
          (state.messages.isNotEmpty || state.carriedItems.isNotEmpty)) {
        _set(state.copyWith(loading: false));
        return;
      }
      _set(CoachState(
        threadId: thread.id,
        messages: rows.map(_toMessage).toList(),
        loading: false,
        carriedItems: force ? const [] : state.carriedItems,
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
        await _restore(force: true); // replace the deleted thread's state
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
      // Distil AFTER the reply is on screen, never before: extraction is
      // background work and must never add latency to the turn the user is
      // waiting on (ADR 0016 decision 5). Unawaited on purpose — a failure
      // here is invisible by design.
      unawaited(maybeExtract());
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

      // A tool call is UNTRUSTED: bounds-check it before it can become a
      // confirm card (review #82). A refused call degrades to prose, never to
      // a silently-wrong proposal.
      ToolDraft? draft;
      if (reply.toolJson != null) {
        final parsed = const ToolCallParser().parse(reply.toolJson!);
        draft = parsed.draft;
        if (draft == null) {
          debugPrint('vita tool refused: ${parsed.rejection}');
        }
      }
      final text = reply.text.trim().isNotEmpty
          ? reply.text
          : (draft != null
              ? 'Want me to log this?'
              : "I couldn't work that one out — could you say it another way?");
      await persistReply(text);
      if (draft != null) {
        // The text tool is single-food by schema. If we are still holding the
        // real photographed items, the user means the MEAL, not one dish — so
        // propose all of them, with the macros the tool call could not carry.
        final carried = state.carriedItems;
        final single = draft;
        // Expand to the whole photographed meal ONLY when the tool call is
        // actually about it. Otherwise a later, unrelated "log my chai" would
        // propose the stale meal instead of the chai (review #99).
        final aboutTheMeal = single is LogFoodDraft &&
            carried.any((i) => _sameFood(i.name, single.name));
        if (carried.isNotEmpty && single is LogFoodDraft && aboutTheMeal) {
          _set(state.copyWith(
            pendingDrafts: carried
                .map((i) => LogFoodDraft(
                      meal: single.meal,
                      name: i.name,
                      energyKcal: i.energyKcal,
                      proteinG: i.proteinG,
                      carbG: i.carbG,
                      fatG: i.fatG,
                      grams: i.grams,
                    ))
                .toList(),
            carriedItems: const [], // consumed
          ));
        } else {
          // Not about the photo: drop the carry so it cannot resurface later.
          _set(state.copyWith(pendingDrafts: [draft], carriedItems: const []));
        }
      }
    } on VitaException catch (e) {
      await persistReply(_friendly(e), synthetic: true);
    } catch (e) {
      debugPrint('coach send failed: $e');
      await persistReply(
          "I couldn't reach the network just now. Try again in a moment.",
          synthetic: true);
    }
  }

  /// Hand a PhotoSnap result to the coach: ask for an opinion in words, but
  /// keep the real items (with macros and grams) so that if the user then says
  /// they ate it, the whole meal can be proposed accurately.
  Future<void> handoffFromPhotoSnap(List<SnappedItem> items) async {
    _set(state.copyWith(carriedItems: items));
    final summary = items
        .map((i) => '${i.name} (~${i.energyKcal.round()} kcal, '
            'P${i.proteinG.round()}/C${i.carbG.round()}/F${i.fatG.round()})')
        .join(', ');
    await send('What do you think of this meal for me — $summary? '
        "I'm asking for your opinion, not to log it yet.");
  }

  /// Send a PHOTO turn (the chat attach button).
  ///
  /// The OTHER entry point — "Ask Vita" on a PhotoSnap result — deliberately
  /// does NOT come through here: by design §5 that path already paid for
  /// vision, so it composes the extracted items as text and uses [send], the
  /// ordinary Vita turn. Routing it through a photo method would imply a second
  /// vision call that must not happen.
  Future<void> sendPhoto({
    required String imageBase64,
    String? caption,
  }) async {
    if (state.sending) return;

    final repo = await ref.read(chatRepositoryProvider.future);
    final question = (caption ?? '').trim();
    final threadId = state.threadId ??
        await repo.createThread(
            title: question.isEmpty ? 'Photo' : question,
            userId: ref.read(currentUserIdProvider));

    // Persist the user's turn FIRST; the description is folded in once known.
    final placeholder =
        question.isEmpty ? '[photo]' : '[photo] $question';
    final messageId = await repo.appendMessage(
        threadId: threadId, role: 'user', content: placeholder);

    final history = [...state.messages, CoachMessage(CoachRole.user, placeholder)];
    _set(state.copyWith(
        threadId: threadId, messages: history, sending: true, loading: false));

    Future<void> finish(String text, {bool synthetic = false}) async {
      await repo.appendMessage(
          threadId: threadId, role: 'vita', content: text, synthetic: synthetic);
      _set(state.copyWith(
        messages: [
          ...state.messages,
          CoachMessage(CoachRole.vita, text, synthetic: synthetic)
        ],
        sending: false,
      ));
    }

    try {
      await ref.read(authServiceProvider).ensureSession();
      final byok = await ref.read(byokStoreProvider).read();

      final vision = await ref.read(photoSnapServiceProvider).converse(
            imageBase64,
            question: question.isEmpty ? null : question,
            context: await _groundingSnapshot(),
            byok: byok,
          );

      // Fold the description into the user's message: it is the visible
      // stand-in for the un-stored photo AND the grounding replayed upstream.
      if (vision.description.isNotEmpty) {
        final withDesc = question.isEmpty
            ? '[photo: ${vision.description}]'
            : '[photo: ${vision.description}] $question';
        await repo.updateMessage(messageId, withDesc);
        final msgs = [...state.messages];
        if (msgs.isNotEmpty) {
          msgs[msgs.length - 1] = CoachMessage(CoachRole.user, withDesc);
          _set(state.copyWith(messages: msgs));
        }
      }
      // Propose a save ONLY when the model judged the user actually wants one
      // (design: a photo alone is not an intent to log). Items were already
      // bounds-checked by parseItems, so they are reused rather than
      // re-estimated from the description (review #95).
      if (vision.shouldProposeLog) {
        final meal = Meal.values
                .where((m) => m.key == vision.meal)
                .firstOrNull ??
            _mealFromClock();
        _set(state.copyWith(
            pendingDrafts: vision.items
                .map((i) => LogFoodDraft(
                      meal: meal,
                      name: i.name,
                      energyKcal: i.energyKcal,
                      proteinG: i.proteinG,
                      carbG: i.carbG,
                      fatG: i.fatG,
                      grams: i.grams,
                    ))
                .toList()));
      }
      await finish(vision.answer);
    } on PhotoSnapException catch (e) {
      await finish(_photoFriendly(e), synthetic: true);
    } catch (e) {
      debugPrint('sendPhoto failed: $e');
      await finish("I couldn't look at that photo just now — please try again.",
          synthetic: true);
    }
  }

  /// Loose match — the model rarely echoes a dish name exactly ("Chana Masala"
  /// vs "Chole/Chana Masala"), so compare on containment either way.
  static bool _sameFood(String a, String b) {
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    return x == y || x.contains(y) || y.contains(x);
  }

  static Meal _mealFromClock() {
    final h = DateTime.now().hour;
    if (h < 11) return Meal.breakfast;
    if (h < 16) return Meal.lunch;
    if (h < 21) return Meal.dinner;
    return Meal.snack;
  }

  /// A photos-exhausted user can STILL text-chat — the scarce-first charge
  /// order preserved that budget, so say so rather than a flat "limit reached"
  /// (review #94).
  static String _photoFriendly(PhotoSnapException e) {
    if (e.outOfPhotosOnly) {
      return "That's all the photo look-ups for today — but you can still chat "
          'with me, or add your own AI key for unlimited.';
    }
    if (e.budgetExhausted) {
      return "We've chatted a lot today — I reset tomorrow. Add your own AI key "
          '(Me → Your own AI key) to chat without limits.';
    }
    if (e.noFood) {
      return "I couldn't make out any food there — want to tell me what it is?";
    }
    // "Please try again" is bad advice when retrying cannot work. A provider
    // failure needs to say so plainly, and must NOT be dressed up as a
    // connectivity blip the user can fix by moving nearer the router.
    if (e.providerDown) {
      return "My food vision is down right now — that's on our side, not your "
          'connection. Tell me what you ate and I can still help.';
    }
    if (e.signInFailed) {
      return "I couldn't sign in just now, so I can't look at photos. Check "
          'your connection and try again.';
    }
    return "I couldn't look at that photo just now — please try again.";
  }

  /// Write the proposed action. Only reachable from an explicit user tap —
  /// Vita never writes on its own (ADR 0016 decision 2).
  Future<void> confirmDraft() async {
    final drafts = state.pendingDrafts;
    if (drafts.isEmpty) return;
    _set(state.copyWith(clearDraft: true)); // no double-tap
    try {
      final executor = ToolExecutor(
        foodLogs: await ref.read(foodLogRepositoryProvider.future),
        water: await ref.read(waterRepositoryProvider.future),
        weight: await ref.read(weightRepositoryProvider.future),
        userId: ref.read(currentUserIdProvider),
      );
      final now = DateTime.now();
      final ymd = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final lines = <String>[];
      for (final d in drafts) {
        lines.add(await executor.execute(d, date: ymd));
      }
      await _appendVita(
          lines.length == 1 ? lines.single : 'Logged ${lines.length} items.',
          synthetic: true);
    } catch (e) {
      debugPrint('confirmDraft failed: $e');
      await _appendVita("I couldn't save that just now — please try again.",
          synthetic: true);
    }
  }

  /// Discard the proposal. Nothing is written and nothing is said — the user
  /// simply did not want it.
  void dismissDraft() => _set(state.copyWith(clearDraft: true));

  /// Append an assistant line to the visible + stored transcript.
  Future<void> _appendVita(String content, {bool synthetic = false}) async {
    final threadId = state.threadId;
    if (threadId == null) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    await repo.appendMessage(
        threadId: threadId,
        role: 'vita',
        content: content,
        synthetic: synthetic);
    _set(state.copyWith(messages: [
      ...state.messages,
      CoachMessage(CoachRole.vita, content, synthetic: synthetic),
    ]));
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
    final favourites = (ref.read(favouriteFoodsProvider).value ?? const [])
        .map((f) => f.row.name)
        .toList();
    final memory = await ref.read(memoryRepositoryProvider.future);
    final facts = await memory.topFor(ref.read(currentUserIdProvider));
    return CoachContext.build(
        profile: profile,
        targets: targets,
        todayLogs: logs,
        now: now,
        planDay: planDay,
        favouriteFoods: favourites,
        memories: [
          for (final f in facts) (kind: f.kind, content: f.content),
        ]);
  }

  /// How many new turns before a distillation pass runs. Batched, never on the
  /// reply path (ADR 0016 decision 5): the reply turn already has two jobs, and
  /// a third degrades all three on a cheap model. 6 is two or three exchanges —
  /// often enough to feel like it is listening, rare enough to stay inside the
  /// small extraction cap.
  static const extractEveryNTurns = 6;

  /// Distil the current thread if enough has been said since the last pass.
  ///
  /// FIRE-AND-FORGET AND SILENT BY DESIGN. This is background work the user did
  /// not ask for, so a failure — offline, budget spent, provider down — must
  /// never surface as an error or block the conversation. The worst outcome of
  /// a miss is that Vita learns it next time.
  Future<void> maybeExtract() async {
    final threadId = state.threadId;
    if (threadId == null) return;
    try {
      final chat = await ref.read(chatRepositoryProvider.future);
      final thread = await chat.threadById(threadId);
      if (thread == null) return;
      final rows = await chat.messagesOf(threadId);
      if (rows.length - thread.summarizedUpTo < extractEveryNTurns) return;

      final extractor = ref.read(memoryExtractorProvider);
      final byok = await ref.read(byokStoreProvider).read();
      final result = await extractor.extract(
        // Synthetic rows are OUR chrome (budget notices, errors), not the
        // user's words — extracting from them would invent facts about the
        // app rather than the person.
        turns: [
          for (final r in rows.where((r) => !r.synthetic))
            (role: r.role == 'user' ? 'user' : 'assistant', content: r.content),
        ],
        priorSummary: thread.summary,
        byok: byok,
      );

      final memory = await ref.read(memoryRepositoryProvider.future);
      final uid = ref.read(currentUserIdProvider);
      for (final f in result.facts) {
        await memory.remember(
          kind: f.kind,
          content: f.content,
          confidence: f.confidence,
          sourceThreadId: threadId,
          userId: uid,
        );
      }
      // Advance the watermark even when nothing was learned, or a quiet
      // stretch of conversation would re-trigger extraction on every send.
      await chat.saveSummary(threadId,
          summary: result.summary, upTo: rows.length);
    } catch (e) {
      debugPrint('memory extraction skipped: $e');
    }
  }
}

final coachControllerProvider =
    NotifierProvider<CoachController, CoachState>(CoachController.new);

/// Saved conversations for the current user, most recent first.
final chatThreadsProvider = StreamProvider<List<ChatThreadRow>>((ref) async* {
  final repo = await ref.watch(chatRepositoryProvider.future);
  yield* repo.watchThreads(ref.watch(currentUserIdProvider));
});
