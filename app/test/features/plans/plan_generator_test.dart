import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';
import 'package:sakama/features/plans/application/plan_importer.dart';
import 'package:sakama/features/plans/data/plan_generator.dart';

ProfileRecord _profile() => ProfileRecord(
      dob: DateTime(1994, 6, 15), weightKg: 70, heightCm: 175, sex: Sex.male,
      activity: ActivityLevel.moderate, goal: Goal.loseWeight,
      diet: DietPreference.veg, cuisine: CuisinePreference.south,
      conditions: const [HealthCondition.diabetes], onboardingComplete: true);

String _plan({int version = 1, bool dayTypes = true}) =>
    '{"schema_version":$version,"id":"p","name":"AI Plan","goal":"lose_weight",'
    '${dayTypes ? '"day_types":{"normal":{"label":"n"}},' : ''}'
    '"schedule":{"type":"weekly","map":{"mon":"normal"}}}';

/// Drives the generate() orchestration by scripting fetchRaw's results
/// (a String to return, or an Exception to throw) per call.
class _ScriptedGenerator extends EdgeFunctionPlanGenerator {
  _ScriptedGenerator(this._script);
  final List<Object> _script;
  int calls = 0;

  @override
  Future<String> fetchRaw(ProfileRecord profile, String? byok) async {
    final r = _script[calls++];
    if (r is Exception) throw r;
    return r as String;
  }
}

void main() {
  group('planProfileProjection (PII-light)', () {
    test('sends age (not dob), enum names, and conditions — no user_id/dob', () {
      final p = planProfileProjection(_profile(), DateTime(2026, 8, 3));
      expect(p['age'], 32); // 1994-06-15 → 2026-08-03
      expect(p['sex'], 'male');
      expect(p['goal'], 'loseWeight');
      expect(p['diet'], 'veg');
      expect(p['cuisine'], 'south');
      expect(p['conditions'], ['diabetes']);
      expect(p.containsKey('dob'), isFalse);
      expect(p.containsKey('user_id'), isFalse);
    });
  });

  group('generate() orchestration', () {
    test('valid on the first try → ok, no retry', () async {
      final g = _ScriptedGenerator([_plan()]);
      final r = await g.generate(_profile());
      expect(r, isA<PlanImportOk>());
      expect((r as PlanImportOk).plan.name, 'AI Plan');
      expect(g.calls, 1);
    });

    test('invalid then valid → ok after one silent retry', () async {
      final g = _ScriptedGenerator(['garbage {{{', _plan()]);
      final r = await g.generate(_profile());
      expect(r, isA<PlanImportOk>());
      expect(g.calls, 2);
    });

    test('invalid twice → PlanImportError, exactly two attempts', () async {
      final g = _ScriptedGenerator(['garbage', 'still bad']);
      final r = await g.generate(_profile());
      expect(r, isA<PlanImportError>());
      expect(g.calls, 2);
    });

    test('a too-new schema is NOT retried (a retry cannot fix it)', () async {
      final g = _ScriptedGenerator([_plan(version: 99)]);
      final r = await g.generate(_profile());
      expect((r as PlanImportError).problem,
          PlanImportProblem.unsupportedVersion);
      expect(g.calls, 1, reason: 'no retry on a version gate');
    });

    test('a budget/transport failure propagates as PlanGenerationException',
        () async {
      final g = _ScriptedGenerator(
          [PlanGenerationException('daily limit reached', budgetExhausted: true)]);
      await expectLater(
        g.generate(_profile()),
        throwsA(isA<PlanGenerationException>()
            .having((e) => e.budgetExhausted, 'budgetExhausted', isTrue)),
      );
      expect(g.calls, 1);
    });
  });

  /// The gateway refuses a generated plan below the clinical calorie floor.
  /// Reading that refusal correctly is what separates "adjust your goal" from
  /// "try again in a minute", and the body's shape is not guaranteed.
  group('describesUnsafePlan', () {
    test('recognises the refusal as a decoded map', () {
      expect(describesUnsafePlan({'error': 'unsafe_plan'}), isTrue);
    });

    test('recognises it as a raw JSON string', () {
      expect(describesUnsafePlan('{"error":"unsafe_plan"}'), isTrue);
    });

    test('an ordinary outage is NOT read as a safety refusal', () {
      // Getting this wrong tells a user to change their goal when the real
      // answer is to retry in a minute.
      expect(describesUnsafePlan({'error': 'provider_error'}), isFalse);
      expect(describesUnsafePlan('{"error":"provider_error"}'), isFalse);
      expect(describesUnsafePlan(null), isFalse);
      expect(describesUnsafePlan(''), isFalse);
      expect(describesUnsafePlan(const <String, dynamic>{}), isFalse);
      expect(describesUnsafePlan(42), isFalse);
    });
  });
}
