import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/plans/application/plan_importer.dart';
import 'package:sakama/features/plans/domain/plan.dart';

const _importer = PlanImporter();

String _plan({int version = kPlanSchemaVersion, bool dayTypes = true}) =>
    '{"schema_version":$version,"id":"p","name":"Reset","goal":"detox",'
    '${dayTypes ? '"day_types":{"normal":{"label":"n"}},' : ''}'
    '"schedule":{"type":"weekly","map":{"mon":"normal"}}}';

void main() {
  group('PlanImporter.validate', () {
    test('a well-formed current-version plan is accepted', () {
      final r = _importer.validate(_plan());
      expect(r, isA<PlanImportOk>());
      final ok = r as PlanImportOk;
      expect(ok.plan.name, 'Reset');
      expect(ok.config, isNotEmpty);
    });

    test('empty / whitespace input is rejected as empty', () {
      expect((_importer.validate('') as PlanImportError).problem,
          PlanImportProblem.empty);
      expect((_importer.validate('   \n ') as PlanImportError).problem,
          PlanImportProblem.empty);
    });

    test('malformed JSON is rejected, not crashed (note 1)', () {
      expect((_importer.validate('{not valid') as PlanImportError).problem,
          PlanImportProblem.malformedJson);
    });

    test('a non-object top level is rejected (note 1)', () {
      expect((_importer.validate('[1,2,3]') as PlanImportError).problem,
          PlanImportProblem.malformedJson);
      expect((_importer.validate('"a string"') as PlanImportError).problem,
          PlanImportProblem.malformedJson);
    });

    test('a schema newer than the client is rejected (note 2)', () {
      final r =
          _importer.validate(_plan(version: kPlanSchemaVersion + 1)) as PlanImportError;
      expect(r.problem, PlanImportProblem.unsupportedVersion);
      expect(r.message, contains('newer version'));
    });

    test('the current schema version is accepted (boundary)', () {
      expect(_importer.validate(_plan(version: kPlanSchemaVersion)),
          isA<PlanImportOk>());
    });

    test('a plan with no day types is rejected as inert', () {
      expect(
          (_importer.validate(_plan(dayTypes: false)) as PlanImportError).problem,
          PlanImportProblem.noDayTypes);
    });

    test('config is stored verbatim (trimmed) so the engine reads what was authored',
        () {
      final raw = '  ${_plan()}  ';
      final ok = _importer.validate(raw) as PlanImportOk;
      expect(ok.config, _plan()); // trimmed, otherwise identical
    });
  });
}
