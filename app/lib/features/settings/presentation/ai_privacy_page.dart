import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';

/// AI & privacy settings (#60). The user can turn AI features on or off any
/// time; the page also restates exactly what each feature sends and to whom,
/// so the disclosure is always reachable, not just at first use.
class AiPrivacyPage extends ConsumerWidget {
  const AiPrivacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(aiConsentProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Treat never-asked as "off" for the toggle's visual state; flipping it on
    // records explicit consent.
    final enabled = consent.value ?? false;

    return Semantics(
      identifier: 'ai-privacy-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('AI & privacy')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Semantics(
                identifier: 'ai-enabled-toggle',
                child: SwitchListTile(
                  title: const Text('Use AI features'),
                  subtitle: Text(enabled
                      ? 'PhotoSnap, AI estimates and Coach are on.'
                      : 'PhotoSnap, AI estimates and Coach are off.'),
                  value: enabled,
                  onChanged: consent.isLoading
                      ? null
                      : (v) => ref.read(aiConsentProvider.notifier).set(v),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('What each feature sends', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'When AI is on, these features send data off this phone to work:',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 12),
            _row(text, 'PhotoSnap', 'the food photo you take'),
            _row(text, 'AI estimate', 'the dish name you type'),
            _row(
                text,
                'Coach (Vita)',
                'your recent food log and your profile — including any health '
                    'conditions you set (for example diabetes or PCOS)'),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Your data goes to our AI provider (OpenRouter, using Google '
                'Gemini) on a paid tier that does not train on it. We do not '
                'sell your data. Turning AI off stops all of the above; the '
                'rest of Sakama keeps working offline.',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(TextTheme text, String title, String what) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: RichText(
          text: TextSpan(style: text.bodyMedium, children: [
            TextSpan(
                text: '$title: ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: what),
            const TextSpan(text: '.'),
          ]),
        ),
      );
}
