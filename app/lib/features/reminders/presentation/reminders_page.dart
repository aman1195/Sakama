import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/kit/kit.dart';
import '../../../core/providers/app_providers.dart';
import '../data/reminder_store.dart';
import '../domain/reminder_plan.dart';

/// Where someone chooses to be interrupted.
///
/// EVERY SWITCH STARTS OFF. The rows arrive pre-filled with sensible times so
/// turning one on is a single tap, but a time is a suggestion of WHEN, never a
/// decision to notify.
///
/// Permission is asked for on the FIRST switch that goes on, not when the page
/// opens — a prompt for a feature nobody has chosen yet is how an app gets
/// denied once and forever. If the user says no, the switch goes back off,
/// because a switch that says "on" while the OS blocks it is a lie.
class RemindersPage extends ConsumerStatefulWidget {
  const RemindersPage({super.key});
  @override
  ConsumerState<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends ConsumerState<RemindersPage> {
  List<ReminderSetting> _settings = const [];
  bool _loading = true;
  String _notice = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(reminderStoreProvider);
    final saved = await store.load();
    if (!mounted) return;
    setState(() {
      // Saved rows win; anything never touched shows its suggestion, off.
      _settings = [
        for (final s in ReminderStore.suggested)
          saved.firstWhere(
            (x) => x.kind == s.kind && x.meal == s.meal,
            orElse: () => s,
          )
      ];
      _loading = false;
    });
  }

  String _label(ReminderSetting s) => switch (s.kind) {
        ReminderKind.meal => s.meal?.label ?? 'Meal',
        ReminderKind.weighIn => 'Weigh-in',
        ReminderKind.weeklyDigest => 'Weekly summary',
        ReminderKind.fastingEdge => 'Eating window',
        ReminderKind.morningNudge => 'Morning note',
      };

  String _sub(ReminderSetting s) {
    final t = s.minuteOfDay ?? 0;
    final time = '${(t ~/ 60).toString().padLeft(2, '0')}:'
        '${(t % 60).toString().padLeft(2, '0')}';
    return switch (s.kind) {
      // Saying so on the row is the honest version of the suppression rule —
      // otherwise a reminder that never arrives looks broken.
      ReminderKind.meal => '$time, only if nothing is logged yet',
      ReminderKind.weighIn => 'Mondays at $time, only if you have not',
      ReminderKind.weeklyDigest => 'Sundays at $time',
      _ => time,
    };
  }

  Future<void> _toggle(ReminderSetting s, bool on) async {
    if (on) {
      final granted =
          await ref.read(reminderSchedulerProvider).requestPermission();
      if (!mounted) return;
      if (!granted) {
        setState(() => _notice =
            'Notifications are off for Sakama. Turn them on in Settings and '
            'come back.');
        return; // the switch stays off, because it would be lying
      }
    }
    final next = [
      for (final x in _settings)
        if (x.kind == s.kind && x.meal == s.meal)
          ReminderSetting(
              kind: x.kind,
              enabled: on,
              minuteOfDay: x.minuteOfDay,
              meal: x.meal,
              weekday: x.weekday)
        else
          x
    ];
    setState(() {
      _settings = next;
      _notice = '';
    });
    await _persistAndReschedule(next);
  }

  Future<void> _pickTime(ReminderSetting s) async {
    final t = s.minuteOfDay ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: t ~/ 60, minute: t % 60),
    );
    if (picked == null || !mounted) return;
    final next = [
      for (final x in _settings)
        if (x.kind == s.kind && x.meal == s.meal)
          ReminderSetting(
              kind: x.kind,
              enabled: x.enabled,
              minuteOfDay: picked.hour * 60 + picked.minute,
              meal: x.meal,
              weekday: x.weekday)
        else
          x
    ];
    setState(() => _settings = next);
    await _persistAndReschedule(next);
  }

  Future<void> _persistAndReschedule(List<ReminderSetting> next) async {
    await ref.read(reminderStoreProvider).save(next);
    await ref.read(reminderSyncProvider.future).then((s) => s.reschedule());
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'reminders-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('Reminders')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(Sk.lg, Sk.md, Sk.lg, Sk.xxl),
                children: [
                  Text(
                    'All off unless you turn them on. A meal reminder stays '
                    'quiet if you have already logged that meal.',
                    style: text.bodyMedium
                        ?.copyWith(color: Theme.of(context).hintColor),
                  ),
                  if (_notice.isNotEmpty) ...[
                    const SizedBox(height: Sk.md),
                    Text(_notice,
                        key: const Key('reminders-notice'),
                        style: text.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: Sk.md),
                  for (final s in _settings)
                    Semantics(
                      identifier: 'reminder-${s.kind.name}'
                          '${s.meal == null ? '' : '-${s.meal!.key}'}',
                      child: SwitchListTile(
                        value: s.enabled,
                        onChanged: (v) => _toggle(s, v),
                        title: Text(_label(s)),
                        subtitle: Text(_sub(s)),
                        secondary: IconButton(
                          icon: const Icon(Icons.schedule),
                          tooltip: 'Change the time',
                          onPressed: () => _pickTime(s),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
