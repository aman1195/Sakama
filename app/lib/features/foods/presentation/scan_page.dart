import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scan_result_view.dart';

/// Barcode scanner: live camera → first stable barcode → resolve + confirm-log
/// via [ScanResultView]. The camera surface is intentionally thin; all the
/// resolve/confirm/log logic (and its tests) lives in ScanResultView, which
/// needs no camera.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final _controller = MobileScannerController();
  String? _barcode; // once set, we stop scanning and show the result sheet

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_barcode != null) return; // already handling one
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    setState(() => _barcode = code);
    _controller.stop();
  }

  void _reset() {
    setState(() => _barcode = null);
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'scan-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('Scan barcode')),
        body: Column(
          children: [
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Camera unavailable: ${error.errorCode.name}.\n'
                      'Grant camera access in Settings, or add the food '
                      'manually.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            if (_barcode != null)
              SafeArea(
                top: false,
                child: ScanResultView(barcode: _barcode!, onDone: _reset),
              ),
          ],
        ),
      ),
    );
  }
}
