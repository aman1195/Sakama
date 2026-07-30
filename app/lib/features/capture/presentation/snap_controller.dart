import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/app_providers.dart';
import '../data/photosnap_service.dart';
import '../domain/snap_draft.dart';
import '../domain/snap_flow.dart';

/// Drives the PhotoSnap flow. Camera capture is injectable (a function that
/// returns base64 JPEG bytes) so the whole analyze→confirm→log path is testable
/// without a camera, exactly like the barcode split.
class SnapController extends Notifier<SnapState> {
  @override
  SnapState build() => const SnapIdle();

  /// Default capture: camera at reduced resolution/quality (bandwidth on Indian
  /// mobile data + the function's ~6MB guard). Returns null if the user backs
  /// out of the camera.
  Future<String?> _captureFromCamera() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (file == null) return null;
    return base64Encode(await file.readAsBytes());
  }

  /// Capture (or accept an injected [imageBase64] in tests) → analyze → confirm.
  Future<void> snap({
    Future<String?> Function()? capture,
    String? imageBase64,
  }) async {
    // Capture is INSIDE error handling (review #57): pickImage throws on a
    // denied permission (PlatformException 'camera_access_denied'), no camera,
    // or a concurrent request. Unhandled, that left the flagship FAB hung on
    // the analyzing spinner forever. Map it to a Settings-flavoured state.
    final String? image;
    try {
      image = imageBase64 ?? await (capture ?? _captureFromCamera)();
    } catch (e) {
      debugPrint('camera unavailable: $e');
      state = _isPermissionError(e)
          ? const SnapPermissionDenied()
          : const SnapError();
      return;
    }
    if (image == null) return; // user cancelled the camera
    state = const SnapAnalyzing();
    try {
      await ref.read(authServiceProvider).ensureSession(); // anon-first
      final byok = await ref.read(byokStoreProvider).read();
      final service = ref.read(photoSnapServiceProvider);
      final items = await service.analyze(image, byok: byok);
      state = SnapReady(items.map(SnapDraft.new).toList());
    } on PhotoSnapException catch (e) {
      state = e.budgetExhausted
          ? const SnapBudgetExhausted()
          : e.noFood
              ? const SnapNoFood()
              : const SnapError();
    } catch (e) {
      debugPrint('snap failed: $e');
      state = const SnapError();
    }
  }

  static bool _isPermissionError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('access_denied') ||
        s.contains('permission') ||
        s.contains('denied');
  }

  void reset() => state = const SnapIdle();

  /// Log every kept draft to today's diary as a photo item. Returns how many
  /// were logged (0 if the state isn't ready). Each row: loggedVia='photo'.
  Future<int> logKept(String todayYmd) async {
    final s = state;
    if (s is! SnapReady) return 0;
    final kept = s.drafts.where((d) => d.keep).toList();
    if (kept.isEmpty) return 0;
    final repo = await ref.read(foodLogRepositoryProvider.future);
    final meal = _mealForNow();
    final userId = ref.read(currentUserIdProvider);
    for (final d in kept) {
      await repo.add(
        date: todayYmd,
        meal: meal,
        name: d.item.name,
        energyKcal: d.energyKcal,
        proteinG: d.proteinG,
        carbG: d.carbG,
        fatG: d.fatG,
        grams: d.grams,
        loggedVia: 'photo',
        userId: userId,
      );
    }
    return kept.length;
  }

  static String _mealForNow() {
    final h = DateTime.now().hour;
    if (h < 11) return 'breakfast';
    if (h < 16) return 'lunch';
    if (h < 21) return 'dinner';
    return 'snack';
  }
}

final snapControllerProvider =
    NotifierProvider<SnapController, SnapState>(SnapController.new);
