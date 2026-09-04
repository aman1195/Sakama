import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/media/data/photo_capture.dart';

/// A stored photo is a different job from a photo sent to a vision model, and
/// the settings are what make the `.jpg` naming and the `image/jpeg`
/// declaration true rather than hoped for.
void main() {
  test('a stored photo gets more resolution than a PhotoSnap capture', () {
    // PhotoSnap uses 1024/80 because it feeds a model with a request-size
    // guard. This one is rendered back to the user, possibly years later.
    expect(PhotoCapture.maxEdge, 1200.0);
    expect(PhotoCapture.quality, 85);
  });

  test('it stays small enough to queue on mobile data', () {
    // A ceiling that a phone screen can use, not a ceiling a camera can reach.
    expect(PhotoCapture.maxEdge, lessThanOrEqualTo(2048.0));
    expect(PhotoCapture.quality, inInclusiveRange(75, 90),
        reason: 'below this banding shows on skin; above it, size runs away');
  });
}
