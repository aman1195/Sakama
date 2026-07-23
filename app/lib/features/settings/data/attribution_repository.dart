import 'package:drift/drift.dart';

import '../../../core/db/database.dart';

/// One (source, licence) pair actually present in the shipped data.
class SourceUsage {
  const SourceUsage({
    required this.source,
    required this.licence,
    required this.rowCount,
    required this.isOdbl,
  });

  final String source;
  final String licence;
  final int rowCount;

  /// True when the rows live in the segregated ODbL table (off_foods).
  final bool isOdbl;
}

/// Derives the attribution list FROM THE DATA, not from a hand-maintained list.
///
/// This is deliberate: a bundled dataset cannot ship uncredited, because the
/// credits screen is generated from the `source`/`licence` provenance columns
/// every row is required to carry (CLAUDE.md rule 7). Add a source without an
/// attribution entry and it renders as "uncredited" rather than silently
/// vanishing.
class AttributionRepository {
  AttributionRepository(this._db);
  final SakamaDatabase _db;

  Future<List<SourceUsage>> usedSources() async {
    final out = <SourceUsage>[];

    final fSource = _db.foods.source;
    final fLicence = _db.foods.licence;
    final fCount = _db.foods.id.count();
    final foodsQuery = _db.selectOnly(_db.foods)
      ..addColumns([fSource, fLicence, fCount])
      ..groupBy([fSource, fLicence]);
    for (final r in await foodsQuery.get()) {
      out.add(SourceUsage(
        source: r.read(fSource)!,
        licence: r.read(fLicence)!,
        rowCount: r.read(fCount) ?? 0,
        isOdbl: false,
      ));
    }

    // The ODbL table is queried separately and flagged, because its
    // share-alike posture differs (CLAUDE.md rule 5).
    final oSource = _db.offFoods.source;
    final oLicence = _db.offFoods.licence;
    final oCount = _db.offFoods.id.count();
    final offQuery = _db.selectOnly(_db.offFoods)
      ..addColumns([oSource, oLicence, oCount])
      ..groupBy([oSource, oLicence]);
    for (final r in await offQuery.get()) {
      out.add(SourceUsage(
        source: r.read(oSource)!,
        licence: r.read(oLicence)!,
        rowCount: r.read(oCount) ?? 0,
        isOdbl: true,
      ));
    }

    out.sort((a, b) => b.rowCount.compareTo(a.rowCount));
    return out;
  }
}
