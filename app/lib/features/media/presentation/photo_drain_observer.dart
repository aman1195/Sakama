import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';

/// Empties the photo queue whenever there is a plausible reason it might
/// succeed, and never at a moment the user would notice.
///
/// WITHOUT THIS, NOTHING CALLS THE DRAIN. The queue, the uploader and the
/// capture path all shipped before anything triggered them: a photo taken
/// offline would sit on disk forever, correctly and uselessly.
///
/// Two triggers, and both mean "something changed that might have been the
/// blocker":
///
///  - **app resumed** — the usual way a phone regains signal is that the user
///    walks somewhere and opens the app again. A background retry timer is the
///    wrong tool on iOS, which suspends them at its own discretion.
///  - **the signed-in user changed** — a queue built while signed out cannot
///    upload, and the moment it can is the moment someone signs in.
///
/// Fire-and-forget by construction. `drain()` swallows its own failures and
/// returns an outcome nobody here reads, because a photo that will not upload
/// must never become an error in front of someone logging lunch.
///
/// Renders its [child] unchanged — a pure side-effect wrapper, the same shape
/// as `DateRolloverObserver`.
class PhotoDrainObserver extends ConsumerStatefulWidget {
  const PhotoDrainObserver({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<PhotoDrainObserver> createState() => _PhotoDrainObserverState();
}

class _PhotoDrainObserverState extends ConsumerState<PhotoDrainObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A cold start is the most likely moment to be holding a photo from a
    // session that ended offline.
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      final uploader = await ref.read(photoUploaderProvider.future);
      await uploader.drain();
    } catch (e) {
      // Even resolving the provider must not surface here.
      debugPrint('photo drain observer: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_drain());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Signing in is the other moment a stuck queue becomes drainable.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (next != null && next != previous) unawaited(_drain());
    });
    return widget.child;
  }
}
