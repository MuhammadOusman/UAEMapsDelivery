HERE Offline App (scaffold)

This is a minimal example scaffold that integrates with a local stub of the HERE SDK to allow offline UAE map flows to be developed without installing the official HERE SDK.

How to replace the stub with the official HERE SDK (heresdk-explore-flutter-4.25.0.0.250834):

1. Download the official HERE SDK package from your HERE account (the file you referred to).
2. Follow the HERE SDK Flutter installation docs. Typically: unzip the SDK and follow the instructions to add the AARs and platform binaries into the Flutter plugin or add the SDK package as a local pub dependency.
3. Replace the plugin stub in `plugins/here_sdk` with the official plugin files (or change `here_offline_app/pubspec.yaml` to point to the official HERE package path).
4. Update `lib/here_offline_map.dart` to call into the real HERE SDK APIs (MapView, OfflineManager) — the stub provides the same method names used here for development.

I can do the replacement for you if you upload or place the official SDK folder somewhere in the workspace (e.g. `third_party/heresdk/`) and tell me where it is.
