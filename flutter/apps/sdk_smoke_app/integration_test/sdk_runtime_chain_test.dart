import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jumper_sdk/jumper_sdk.dart';

const _coreBinaryPath = String.fromEnvironment('JUMPER_CORE_BIN', defaultValue: '');
const _coreArguments = String.fromEnvironment('JUMPER_CORE_ARGS', defaultValue: '');
const _coreWorkingDirectory = String.fromEnvironment('JUMPER_CORE_WORKDIR', defaultValue: '');
const _coreApiBase = String.fromEnvironment('JUMPER_CORE_API_BASE', defaultValue: 'http://127.0.0.1:20123');
const _coreConfigPath = String.fromEnvironment('JUMPER_CORE_CONFIG_PATH', defaultValue: '');
const _skipStart = String.fromEnvironment('JUMPER_SKIP_START', defaultValue: 'false') == 'true';
const _assumeBinAccessible =
    String.fromEnvironment('JUMPER_ASSUME_BIN_ACCESSIBLE', defaultValue: 'false') == 'true';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sdk client runs start -> proxies -> stop', (tester) async {
    if (!_skipStart) {
      expect(_coreBinaryPath.isNotEmpty, isTrue, reason: 'JUMPER_CORE_BIN is required');
      expect(File(_coreBinaryPath).existsSync(), isTrue, reason: 'Core binary not found');
    }

    final runtimeLaunchOptions = _skipStart
        ? JumperRuntimeLaunchOptions(
            binaryPath: _coreBinaryPath,
            arguments: _splitArgs(_coreArguments),
            workingDirectory: _coreWorkingDirectory.isEmpty ? null : _coreWorkingDirectory,
          )
        : await _buildSandboxedLaunchOptions();
    final sdk = JumperSdkClient(
      coreApiBaseUri: Uri.parse(_coreApiBase),
      runtimeLaunchOptions: runtimeLaunchOptions,
    );

    try {
      if (!_skipStart) {
        await sdk.startCore(profileId: 'integration-profile');
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      var proxyCount = 0;
      Object? lastError;
      for (var i = 0; i < 10; i++) {
        try {
          final proxies = await sdk.getProxies();
          proxyCount = proxies.groups.length;
          // ignore: avoid_print
          print('integration proxy probe #$i count=$proxyCount');
        } catch (error) {
          lastError = error;
          // ignore: avoid_print
          print('integration proxy probe #$i failed: $error');
          proxyCount = 0;
        }
        if (proxyCount > 0) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      expect(proxyCount, greaterThan(0), reason: 'lastError=$lastError');
    } finally {
      if (!_skipStart) {
        await sdk.stopCore();
      }
    }
  });
}

List<String> _splitArgs(String args) {
  return args
      .split(' ')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

Future<JumperRuntimeLaunchOptions> _buildSandboxedLaunchOptions() async {
  if (_assumeBinAccessible) {
    final configPath = _resolveConfigPath();
    if (configPath == null) {
      throw StateError('Unable to resolve core config path');
    }
    final workingDir = _coreWorkingDirectory.isEmpty
        ? File(configPath).parent.path
        : _coreWorkingDirectory;
    return JumperRuntimeLaunchOptions(
      binaryPath: _coreBinaryPath,
      arguments: <String>[
        'run',
        '--disable-color',
        '-c',
        configPath,
        '-D',
        workingDir,
      ],
      workingDirectory: workingDir,
    );
  }

  final sourceBinary = File(_coreBinaryPath);
  if (!sourceBinary.existsSync()) {
    throw StateError('Core binary not found: $_coreBinaryPath');
  }

  final sourceConfigPath = _resolveConfigPath();
  if (sourceConfigPath == null) {
    throw StateError('Unable to resolve core config path');
  }
  final sourceConfig = File(sourceConfigPath);
  if (!sourceConfig.existsSync()) {
    throw StateError('Core config not found: $sourceConfigPath');
  }

  final sandboxRoot = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}jumper-runtime');
  await sandboxRoot.create(recursive: true);

  final binaryName = _coreBinaryPath.split('/').last;
  final copiedBinaryPath = '${sandboxRoot.path}${Platform.pathSeparator}$binaryName';
  final copiedConfigPath = '${sandboxRoot.path}${Platform.pathSeparator}config.json';

  await sourceBinary.copy(copiedBinaryPath);
  await sourceConfig.copy(copiedConfigPath);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', copiedBinaryPath]);
  }

  return JumperRuntimeLaunchOptions(
    binaryPath: copiedBinaryPath,
    arguments: <String>[
      'run',
      '--disable-color',
      '-c',
      copiedConfigPath,
      '-D',
      sandboxRoot.path,
    ],
    workingDirectory: sandboxRoot.path,
  );
}

String? _resolveConfigPath() {
  if (_coreConfigPath.isNotEmpty) {
    return _coreConfigPath;
  }
  final args = _splitArgs(_coreArguments);
  final index = args.indexOf('-c');
  if (index != -1 && index + 1 < args.length) {
    return args[index + 1];
  }
  return null;
}
