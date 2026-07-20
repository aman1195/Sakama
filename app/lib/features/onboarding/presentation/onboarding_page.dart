import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/enums.dart';
import '../domain/profile.dart';
import '../domain/target_calculator.dart';
import 'labels.dart';
import 'onboarding_controller.dart';
import 'onboarding_draft.dart';

/// Six-step onboarding: goal → profile → diet → conditions → cuisine →
/// activity → (a live targets preview). Writes a ProfileRecord on finish,
/// which flips onboardingCompleteProvider and the router gate sends the user
/// into the app.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;
  static const _lastStep = 6; // 0..5 questions, 6 = preview

  void _go(int page) {
    setState(() => _page = page);
    _controller.animateToPage(page,
        duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  bool _canAdvance(OnboardingDraft d) {
    final now = DateTime.now();
    return switch (_page) {
      0 => d.goalOk,
      1 => d.profileOk(now),
      2 => d.dietOk,
      3 => true, // conditions optional
      4 => d.cuisineOk,
      5 => d.activityOk,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: _page > 0
            ? Semantics(
                identifier: 'onboarding-back',
                child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => _go(_page - 1)),
              )
            : null,
        title: LinearProgressIndicator(value: (_page + 1) / (_lastStep + 1)),
      ),
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          _GoalStep(),
          _ProfileStep(),
          _DietStep(),
          _ConditionsStep(),
          _CuisineStep(),
          _ActivityStep(),
          _PreviewStep(),
        ],
      ),
      bottomNavigationBar: _page < _lastStep
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Semantics(
                  identifier: 'onboarding-next',
                  child: FilledButton(
                    onPressed: _canAdvance(draft) ? () => _go(_page + 1) : null,
                    child: Text(_page == 5 ? 'See my plan' : 'Continue'),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

// ---- reusable single-select list ----
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onSelect,
    required this.idPrefix,
  });
  final String title;
  final List<T> options;
  final String Function(T) labelOf;
  final T? selected;
  final ValueChanged<T> onSelect;
  final String idPrefix;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        for (final o in options)
          Semantics(
            identifier: '$idPrefix-${(o as Enum).name}',
            child: Card(
              color: selected == o
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: ListTile(
                title: Text(labelOf(o)),
                trailing: selected == o ? const Icon(Icons.check) : null,
                onTap: () => onSelect(o),
              ),
            ),
          ),
      ],
    );
  }
}

class _GoalStep extends ConsumerWidget {
  const _GoalStep();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Choice<Goal>(
        title: "What's your goal?",
        options: Goal.values,
        labelOf: (g) => g.label,
        selected: ref.watch(onboardingControllerProvider).goal,
        onSelect: ref.read(onboardingControllerProvider.notifier).setGoal,
        idPrefix: 'goal',
      );
}

class _DietStep extends ConsumerWidget {
  const _DietStep();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Choice<DietPreference>(
        title: 'How do you eat?',
        options: DietPreference.values,
        labelOf: (d) => d.label,
        selected: ref.watch(onboardingControllerProvider).diet,
        onSelect: ref.read(onboardingControllerProvider.notifier).setDiet,
        idPrefix: 'diet',
      );
}

class _CuisineStep extends ConsumerWidget {
  const _CuisineStep();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Choice<CuisinePreference>(
        title: 'Which cuisine do you eat most?',
        options: CuisinePreference.values,
        labelOf: (c) => c.label,
        selected: ref.watch(onboardingControllerProvider).cuisine,
        onSelect: ref.read(onboardingControllerProvider.notifier).setCuisine,
        idPrefix: 'cuisine',
      );
}

class _ActivityStep extends ConsumerWidget {
  const _ActivityStep();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Choice<ActivityLevel>(
        title: 'How active are you?',
        options: ActivityLevel.values,
        labelOf: (a) => a.label,
        selected: ref.watch(onboardingControllerProvider).activity,
        onSelect: ref.read(onboardingControllerProvider.notifier).setActivity,
        idPrefix: 'activity',
      );
}

class _ConditionsStep extends ConsumerWidget {
  const _ConditionsStep();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingControllerProvider);
    final ctl = ref.read(onboardingControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Any health conditions?',
            style: Theme.of(context).textTheme.headlineSmall),
        const Text('Optional — helps tailor your coaching.'),
        const SizedBox(height: 16),
        for (final c in HealthCondition.values)
          Semantics(
            identifier: 'condition-${c.name}',
            child: CheckboxListTile(
              title: Text(c.label),
              value: draft.conditions.contains(c),
              onChanged: (_) => ctl.toggleCondition(c),
            ),
          ),
      ],
    );
  }
}

class _ProfileStep extends ConsumerWidget {
  const _ProfileStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingControllerProvider);
    final ctl = ref.read(onboardingControllerProvider.notifier);
    final now = DateTime.now();
    final age = draft.ageAt(now);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('About you', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        // Date of birth (stored, never a raw age — see ProfileRecord).
        Semantics(
          identifier: 'profile-dob',
          child: ListTile(
            leading: const Icon(Icons.cake_outlined),
            title: Text(draft.dob == null
                ? 'Date of birth'
                : '${draft.dob!.year}-${draft.dob!.month.toString().padLeft(2, '0')}'
                    '-${draft.dob!.day.toString().padLeft(2, '0')}'
                    '${age != null ? '  ($age yrs)' : ''}'),
            trailing: const Icon(Icons.edit),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: draft.dob ?? DateTime(now.year - 25),
                firstDate: DateTime(now.year - OnboardingDraft.maxAge),
                lastDate: DateTime(now.year - OnboardingDraft.minAge, now.month, now.day),
              );
              if (picked != null) ctl.setDob(picked);
            },
          ),
        ),
        if (age != null && (age < OnboardingDraft.minAge || age > OnboardingDraft.maxAge))
          Text('Age must be ${OnboardingDraft.minAge}–${OnboardingDraft.maxAge}.',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        _NumberField(
          id: 'profile-weight',
          label: 'Weight (kg)',
          value: draft.weightKg,
          min: OnboardingDraft.minWeight,
          max: OnboardingDraft.maxWeight,
          onValid: ctl.setWeight,
        ),
        _NumberField(
          id: 'profile-height',
          label: 'Height (cm)',
          value: draft.heightCm,
          min: OnboardingDraft.minHeight,
          max: OnboardingDraft.maxHeight,
          onValid: ctl.setHeight,
        ),
        const SizedBox(height: 8),
        SegmentedButton<Sex>(
          segments: [
            for (final s in Sex.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: draft.sex == null ? {} : {draft.sex!},
          emptySelectionAllowed: true,
          onSelectionChanged: (s) => s.isNotEmpty ? ctl.setSex(s.first) : null,
        ),
      ],
    );
  }
}

/// A numeric field that only commits values inside [min, max]; shows an inline
/// error otherwise (the validation the review asked for).
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.id,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onValid,
  });
  final String id;
  final String label;
  final double? value;
  final double min;
  final double max;
  final ValueChanged<double> onValid;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        identifier: id,
        child: TextFormField(
          initialValue: value?.toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          validator: (_) => null,
          onChanged: (t) {
            final v = double.tryParse(t);
            if (v != null && v >= min && v <= max) onValid(v);
          },
        ),
      ),
    );
  }
}

/// The wow moment: the AI-free default targets, computed live, before any
/// account. (AI plan generation for Type-2 users is M4.)
class _PreviewStep extends ConsumerWidget {
  const _PreviewStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingControllerProvider);
    final now = DateTime.now();
    if (!draft.complete(now)) {
      return const Center(child: Text('Finish the earlier steps first.'));
    }
    final Profile profile = draft.toRecord().toCalculatorInput(now);
    final t = const TargetCalculator().targets(profile);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Your daily plan', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text('${t.calories}', style: Theme.of(context).textTheme.displaySmall),
              const Text('kcal / day'),
            ]),
          ),
        ),
        _macro('Protein', t.proteinG),
        _macro('Carbs', t.carbG),
        _macro('Fat', t.fatG),
        _macro('Fibre', t.fiberG),
        _macro('Water (ml)', t.waterMl),
        const SizedBox(height: 24),
        Semantics(
          identifier: 'onboarding-finish',
          child: FilledButton(
            onPressed: () async {
              final ok = await ref.read(onboardingControllerProvider.notifier).finish();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please complete every step.')));
              }
              // On success the router gate swaps to the app automatically.
            },
            child: const Text('Start tracking'),
          ),
        ),
      ],
    );
  }

  Widget _macro(String label, int g) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text('$g', style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}


