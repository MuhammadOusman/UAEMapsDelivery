import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/core.engine.dart';
import 'delivery_strict.dart';

// Credentials are loaded from `lib/secrets.dart` generated from `.env` (run `dart run tool/gen_secrets.dart`)
import 'secrets.dart';
import 'package:here_offline_app/app_theme.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize HERE SDK
  await _initializeHERESDK();

  // Load persisted theme preference
  await AppTheme.load();

  runApp(const MyApp());
}

/// Small helper for storing and notifying theme changes across the app.

Future<void> _initializeHERESDK() async {
  SdkContext.init(IsolateOrigin.main);

  // Use Key/Secret authentication mode
  AuthenticationMode authenticationMode = AuthenticationMode.withKeySecret(kAccessKeyId, kAccessKeySecret);
  SDKOptions sdkOptions = SDKOptions.withAuthenticationMode(authenticationMode);

  try {
    await SDKNativeEngine.makeSharedInstance(sdkOptions);
  } on Exception catch (e) {
    // Initialization failed (likely due to missing/wrong credentials). We continue so the app UI can show instructions.
    debugPrint('HERE SDK initialization failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'HERE UAE Offline Demo',
          theme: ThemeData(primarySwatch: Colors.blue, brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.blue),
          themeMode: mode,
          home: const HereSplash(),
        );
      },
    );
  }
}

class HereSplash extends StatefulWidget {
  const HereSplash({super.key});

  @override
  State<HereSplash> createState() => _HereSplashState();
}

class _HereSplashState extends State<HereSplash> {
  @override
  void initState() {
    super.initState();
    _checkFirstRun();
  }

  Future<void> _checkFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    final _ = prefs.getBool('map_prefetched') ?? false;

    // Wait a short moment so user sees the splash then go to map
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DeliveryStrictScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [CircularProgressIndicator(), SizedBox(height: 12), Text('Preparing HERE Offline...')])),
    );
  }
}
