import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';

/// Gate every AI action (#60). Returns true if the caller may proceed to send
/// data to the provider:
///   * consented (`true`)  -> proceed.
///   * off (`false`)       -> a snackbar points the user at the settings toggle.
///   * never asked (`null`)-> the first-use disclosure sheet; proceed only if
///                            the user turns AI on there.
///
/// Call this BEFORE any code that transmits logged data (open the camera, send
/// a chat turn, request an estimate).
Future<bool> ensureAiConsent(BuildContext context, WidgetRef ref) async {
  final current = await ref.read(aiConsentProvider.future);
  if (current == true) return true;
  if (!context.mounted) return false;

  if (current == false) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('AI features are turned off.'),
        action: SnackBarAction(
          label: 'Turn on',
          onPressed: () => context.push('/ai-privacy'),
        ),
      ),
    );
    return false;
  }

  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const AiDisclosureSheet(),
  );
  if (accepted == true) {
    await ref.read(aiConsentProvider.notifier).set(true);
    return true;
  }
  return false;
}

/// The first-use disclosure. Names exactly what each AI feature sends, the
/// recipient, and the paid-tier/no-training posture (ADR 0011). Pops `true`
/// only when the user explicitly turns AI on.
class AiDisclosureSheet extends StatelessWidget {
  const AiDisclosureSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'ai-disclosure-sheet',
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Only the explanation scrolls. The consent buttons stay PINNED —
            // an accept button hidden below a fold is not informed consent, and
            // this list overflowed a small screen once plan generation was
            // added (large Dynamic Type makes it worse — docs/MOBILE.md).
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Before you use AI', style: text.headlineSmall),
                    const SizedBox(height: 12),
                    Text(
                      'Sakama\'s AI features work by sending some of your data '
                      'off this phone to our AI provider:',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    const _Sends(
                      icon: Icons.photo_camera_outlined,
                      title: 'PhotoSnap',
                      what: 'the food photo you take',
                    ),
                    const _Sends(
                      icon: Icons.search,
                      title: 'AI estimate',
                      what: 'the dish name you type',
                    ),
                    const _Sends(
                      icon: Icons.chat_bubble_outline,
                      title: 'Coach (Vita)',
                      what:
                          'what you type in the chat, your recent food log, '
                          'your profile — including any health conditions you '
                          'set (for example diabetes or PCOS) — and your active '
                          'plan, so its advice fits you',
                    ),
                    const _Sends(
                      icon: Icons.auto_awesome,
                      title: 'Plan generation',
                      what:
                          'your profile — including any health conditions — '
                          'to build a plan for you',
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Your chats are stored only on this phone and are never '
                        'uploaded to our servers. Your data goes to our AI '
                        'provider (OpenRouter, using Google Gemini) on a paid '
                        'tier that does not train on it. We do not sell your '
                        'data. You can turn AI off any time in Me → AI & '
                        'privacy.',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: 'ai-disclosure-decline',
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Not now'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      identifier: 'ai-disclosure-accept',
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Turn on AI'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sends extends StatelessWidget {
  const _Sends({required this.icon, required this.title, required this.what});
  final IconData icon;
  final String title, what;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: text.bodyMedium,
                children: [
                  TextSpan(
                    text: '$title sends ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: what),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
