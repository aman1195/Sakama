import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';

import 'generated/schema.dart';

/// The migration harness required by docs/MOBILE.md and docs/REVIEW.md §6.1:
/// a bad on-device migration destroys user data irrecoverably, so every schema
/// bump must (1) dump a new drift_schemas/drift_schema_vN.json, (2) regenerate
/// test/migration/generated/, and (3) add a vN-1 -> vN data-preservation test
/// here. CI runs this suite on every PR.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('database schema matches the committed v1 snapshot', () async {
    // Creates a fresh db from SakamaDatabase's Dart definitions and diffs it
    // against drift_schemas/drift_schema_v1.json. Fails if the code drifts
    // from the committed snapshot without a new schema version + migration.
    final connection = await verifier.startAt(1);
    final db = SakamaDatabase.withExecutor(connection);
    await verifier.migrateAndValidate(db, 1);
    await db.close();
  });

  // v2 onward: use verifier.startAt(N-1), insert representative rows, migrate,
  // and assert the data survived. See drift's step-by-step migration docs.
}
