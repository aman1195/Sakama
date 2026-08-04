import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/coach/domain/tool_draft.dart';
import 'package:sakama/features/home/domain/day_totals.dart' show Meal;

const _p = ToolCallParser();

String _food({
  String meal = 'lunch',
  String name = 'dal tadka',
  Object kcal = 180,
  Object protein = 9,
  Object carb = 22,
  Object fat = 6,
  Object? grams = 150,
}) =>
    '{"tool":"log_food","arguments":{"meal":"$meal","name":"$name",'
    '"energy_kcal":$kcal,"protein_g":$protein,"carb_g":$carb,"fat_g":$fat'
    '${grams == null ? '' : ',"grams":$grams'}}}';

void main() {
  group('accepts well-formed calls', () {
    test('log_food maps to a draft with a readable summary', () {
      final r = _p.parse(_food());
      expect(r.rejection, isNull);
      final d = r.draft as LogFoodDraft;
      expect(d.meal, Meal.lunch);
      expect(d.name, 'dal tadka');
      expect(d.energyKcal, 180);
      expect(d.grams, 150);
      expect(d.summary, contains('dal tadka'));
      expect(d.summary, contains('180 kcal'));
    });

    test('calories-only food is allowed (no macros stated)', () {
      final r = _p.parse('{"tool":"log_food","arguments":'
          '{"meal":"snack","name":"chai","energy_kcal":90}}');
      expect(r.rejection, isNull,
          reason: '"roughly 90 kcal" is a legitimate, common way to log');
      expect((r.draft as LogFoodDraft).proteinG, 0);
    });

    test('numeric strings are coerced', () {
      final r = _p.parse(_food(kcal: '"180"', protein: '"9"'));
      expect(r.rejection, isNull);
      expect((r.draft as LogFoodDraft).energyKcal, 180);
    });

    test('log_water and log_weight', () {
      expect((_p.parse('{"tool":"log_water","arguments":{"amount_ml":250}}')
              .draft as LogWaterDraft)
          .amountMl, 250);
      expect((_p.parse('{"tool":"log_weight","arguments":{"weight_kg":78.4}}')
              .draft as LogWeightDraft)
          .weightKg, 78.4);
    });
  });

  group('refuses untrusted junk before it can reach a confirm card', () {
    test('not JSON / not an object', () {
      expect(_p.parse('sorry, I can help with that!').rejection,
          ToolRejection.notJson);
      expect(_p.parse('[1,2,3]').rejection, ToolRejection.notJson);
    });

    test('an unknown or absent tool', () {
      expect(_p.parse('{"tool":"delete_everything"}').rejection,
          ToolRejection.unknownTool);
      expect(_p.parse('{}').rejection, ToolRejection.unknownTool);
    });

    test('missing required fields', () {
      expect(
          _p.parse('{"tool":"log_food","arguments":{"name":"x"}}').rejection,
          ToolRejection.missingField);
      expect(_p.parse('{"tool":"log_water","arguments":{}}').rejection,
          ToolRejection.missingField);
    });

    test('an invented meal slot is refused, not coerced', () {
      expect(_p.parse(_food(meal: 'brunch')).rejection,
          ToolRejection.missingField);
    });

    test('absurd calories never become a draft', () {
      expect(_p.parse(_food(kcal: 999999, protein: 0, carb: 0, fat: 0))
          .rejection, ToolRejection.outOfRange);
      expect(_p.parse(_food(kcal: 0, protein: 0, carb: 0, fat: 0)).rejection,
          ToolRejection.outOfRange);
    });

    test('negative or impossible macros', () {
      expect(_p.parse(_food(protein: -5)).rejection, ToolRejection.outOfRange);
      expect(_p.parse(_food(protein: 900)).rejection, ToolRejection.outOfRange);
    });

    test('impossible portion weight', () {
      expect(_p.parse(_food(grams: 99999)).rejection, ToolRejection.outOfRange);
      expect(_p.parse(_food(grams: 0)).rejection, ToolRejection.outOfRange);
    });

    test('water and weight bounds', () {
      expect(_p.parse('{"tool":"log_water","arguments":{"amount_ml":99999}}')
          .rejection, ToolRejection.outOfRange);
      expect(_p.parse('{"tool":"log_weight","arguments":{"weight_kg":5}}')
          .rejection, ToolRejection.outOfRange);
      expect(_p.parse('{"tool":"log_weight","arguments":{"weight_kg":900}}')
          .rejection, ToolRejection.outOfRange);
    });

    test('NaN / Infinity are not numbers we accept', () {
      // JSON has no NaN literal, so these arrive as strings from a sloppy model.
      expect(_p.parse(_food(kcal: '"NaN"')).rejection,
          ToolRejection.missingField);
      expect(_p.parse(_food(kcal: '"Infinity"')).rejection,
          ToolRejection.missingField,
          reason: 'non-finite is rejected at coercion, before any comparison');
    });

    test('an over-long name is refused (a pasted paragraph, not a food)', () {
      expect(_p.parse(_food(name: 'a' * 200)).rejection,
          ToolRejection.outOfRange);
    });
  });

  group('Atwater cross-check — the magnitude guard confirm cannot provide', () {
    test('calories wildly inconsistent with stated macros are refused', () {
      // 9P + 22C + 6F ≈ 178 kcal; claiming 800 is the plausible-looking error
      // a distracted tap would approve.
      expect(_p.parse(_food(kcal: 800)).rejection,
          ToolRejection.macrosInconsistent);
    });

    test('a normal rounding discrepancy is still accepted', () {
      // ~178 by Atwater, stated 190 — within tolerance, a real-world rounding.
      expect(_p.parse(_food(kcal: 190)).rejection, isNull);
    });
  });
}
