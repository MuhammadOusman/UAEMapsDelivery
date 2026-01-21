import 'dart:io';

/// Simple generator: reads .env from project root and writes `here_offline_app/lib/secrets.dart`.
/// Run: `dart run tool/gen_secrets.dart` from the project root (`UAEMapsDelivery`).

void main() {
  final envFile = _findEnvFile();
  final env = <String, String>{};

  if (envFile == null) {
    print('No .env file found. Writing placeholder secrets.dart');
  } else {
    print('Using .env file at: ${envFile.path}');
    final lines = envFile.readAsLinesSync();
    for (final l in lines) {
      final line = l.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split('=');
      if (parts.length < 2) continue;
      final key = parts[0].trim();
      final value = parts.sublist(1).join('=').trim();
      env[key] = value;
    }
  }

  final accessKeyId = env['ACCESS_KEY_ID'] ?? 'YOUR_ACCESS_KEY_ID';
  final accessKeySecret = env['ACCESS_KEY_SECRET'] ?? 'YOUR_ACCESS_KEY_SECRET';

  final outDir = Directory('here_offline_app/lib');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final outFile = File('${outDir.path}/secrets.dart');

  final content = '''// GENERATED - DO NOT EDIT
// Generated from .env by tool/gen_secrets.dart

const String kAccessKeyId = r"$accessKeyId";
const String kAccessKeySecret = r"$accessKeySecret";
''';

  outFile.writeAsStringSync(content);
  print('Wrote ${outFile.path}');
}

File? _findEnvFile() {
  final candidates = [
    File('.env'),
    File('../.env'),
    File('../../.env'),
  ];
  for (final f in candidates) {
    if (f.existsSync()) return f;
  }
  return null;
}
