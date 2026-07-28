import 'food.dart';

/// The outcome of resolving a scanned barcode, as a VALUE rather than a thrown
/// exception. Modelling the failure modes as data (not errors) keeps them off
/// the Riverpod error path — which in Riverpod 3 auto-retries, so a thrown
/// "rate limited" would loop in loading forever — and makes the UI a plain
/// switch over explicit states.
sealed class BarcodeResult {
  const BarcodeResult();
}

/// OFF (or the cache) resolved the product.
class BarcodeFound extends BarcodeResult {
  const BarcodeFound(this.food);
  final Food food;
}

/// A well-formed "no such product" — OFF simply has no record.
class BarcodeNotFound extends BarcodeResult {
  const BarcodeNotFound();
}

/// OFF rate-limited us (HTTP 429). Recoverable: try again shortly.
class BarcodeRateLimited extends BarcodeResult {
  const BarcodeRateLimited();
}

/// The lookup failed (no network / server error) AND the cache had nothing.
class BarcodeOffline extends BarcodeResult {
  const BarcodeOffline();
}
