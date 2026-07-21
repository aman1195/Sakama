import 'package:flutter/material.dart';

/// Full-screen, non-dismissible block shown when the running build is below the
/// server-set floor (MOBILE.md min-version gate). Because we cannot hotfix, this
/// is how a known-broken build is taken out of service: bump min_supported_build
/// in app_config and every old client lands here on next launch.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Semantics(
        identifier: 'update-required',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.system_update, size: 72, color: scheme.primary),
                const SizedBox(height: 24),
                Text('Update Sakama',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'This version is no longer supported. Please update to the '
                  'latest version to keep tracking safely.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
