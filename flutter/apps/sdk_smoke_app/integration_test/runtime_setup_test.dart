import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jumper_sdk/jumper_sdk.dart';

const _workspaceBasePath = String.fromEnvironment('JUMPER_WORKSPACE_BASE_PATH', defaultValue: '');
const _runtimeVersion = String.fromEnvironment('JUMPER_RUNTIME_VERSION', defaultValue: '1.12.22');
const _platformArch = String.fromEnvironment('JUMPER_RUNTIME_PLATFORM_ARCH', defaultValue: 'darwin-arm64');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('setup and inspect runtime in app container', (tester) async {
    if (_workspaceBasePath.isEmpty) {
      fail('JUMPER_WORKSPACE_BASE_PATH is required');
    }

    final sdk = JumperSdkClient();
    final setup = await sdk.setupRuntime(
      version: _runtimeVersion,
      platformArch: _platformArch,
      basePath: _workspaceBasePath,
    );
    expect(setup['installed'], true);

    final inspect = await sdk.inspectRuntime(
      version: _runtimeVersion,
      platformArch: _platformArch,
      basePath: _workspaceBasePath,
    );
    expect(inspect['ready'], true);
    expect(inspect['binaryExists'], true);
    expect(inspect['configExists'], true);

    final binaryPath = inspect['binaryPath'] as String?;
    final configPath = inspect['configPath'] as String?;
    expect(binaryPath, isNotNull);
    expect(configPath, isNotNull);
    expect(File(binaryPath!).existsSync(), isTrue);
    expect(File(configPath!).existsSync(), isTrue);
  });
}
