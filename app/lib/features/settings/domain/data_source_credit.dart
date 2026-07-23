// Attribution metadata for every data source that can appear in the reference
// tables. Rendered by the Data Sources screen.
//
// Attribution is a LEGAL OBLIGATION for some licences, not a courtesy
// (ASSET_CREDITS.md). The elements below are the ones CC BY 4.0 §3(a) requires
// — creator, copyright/licence notice, licence link, source link, disclaimer,
// and a modification note — so a CC-BY source can be credited correctly the
// day it lands. CC0 needs none of it but we credit anyway.

/// What a source needs shown, and why.
class DataSourceCredit {
  const DataSourceCredit({
    required this.title,
    required this.creator,
    required this.licenceName,
    this.licenceUrl,
    this.sourceUrl,
    required this.obligation,
    this.modification,
    this.disclaimer =
        'Provided "as is", without warranties of any kind. Nutrition values '
        'are references, not medical advice.',
  });

  final String title;
  final String creator;
  final String licenceName;
  final String? licenceUrl;
  final String? sourceUrl;

  /// Plain-language statement of what the licence requires of us.
  final String obligation;

  /// Required by CC BY 4.0 §3(a)(1)(B) whenever we transform the data.
  final String? modification;

  final String disclaimer;
}

/// Keyed by the `source` column value (CLAUDE.md rule 7).
const kDataSourceCredits = <String, DataSourceCredit>{
  'usda_fdc': DataSourceCredit(
    title: 'USDA FoodData Central — SR Legacy',
    creator: 'U.S. Department of Agriculture, Agricultural Research Service',
    licenceName: 'CC0 1.0 / Public Domain',
    licenceUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
    sourceUrl: 'https://fdc.nal.usda.gov/',
    obligation: 'Public domain — no attribution required. Credited voluntarily.',
    modification: 'Modified by Sakama: values kept per 100 g, a subset of '
        'fields retained, and records re-keyed.',
  ),
  'sample': DataSourceCredit(
    title: 'Sakama sample data (placeholder)',
    creator: 'Sakama',
    licenceName: 'Internal placeholder',
    obligation: 'None — our own approximate placeholder values.',
    modification: 'APPROXIMATE values for common Indian dishes, included so '
        'search works before a licensed Indian corpus lands. Not measured '
        'data — treat with lower confidence.',
  ),
  'openfoodfacts': DataSourceCredit(
    title: 'Open Food Facts',
    creator: 'Open Food Facts contributors',
    licenceName: 'Open Database License (ODbL)',
    licenceUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
    sourceUrl: 'https://world.openfoodfacts.org/',
    obligation: 'Attribution REQUIRED, and share-alike applies to derived '
        'databases. Kept in a separate, source-tagged table.',
    modification: 'Modified by Sakama: filtered to a regional subset and '
        're-keyed.',
  ),
  'ai_estimate': DataSourceCredit(
    title: 'AI-estimated nutrition',
    creator: 'Sakama AI (model-generated)',
    licenceName: 'Generated content',
    obligation: 'None. Shown with a confidence score.',
    modification: 'ESTIMATED, not measured. Grounded on reference data where '
        'possible; always lower confidence than a verified source.',
  ),
};

/// Fallback so an unknown/new source can never render as a blank credit —
/// it shows up loudly instead, which is the point of generating this from data.
DataSourceCredit creditFor(String source, String licence) =>
    kDataSourceCredits[source] ??
    DataSourceCredit(
      title: source,
      creator: 'Unknown — uncredited source',
      licenceName: licence,
      obligation: 'UNVERIFIED: this source has no attribution entry. It must '
          'not ship until its licence and credit are confirmed.',
    );
