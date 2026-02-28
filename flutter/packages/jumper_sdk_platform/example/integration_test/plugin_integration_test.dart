import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:jumper_sdk_platform/jumper_sdk_platform.dart';

const _workspaceBasePath = String.fromEnvironment(
  'JUMPER_WORKSPACE_BASE_PATH',
  defaultValue: '',
);
const _runtimeVersion = String.fromEnvironment(
  'JUMPER_RUNTIME_VERSION',
  defaultValue: '1.12.22',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getPlatformVersion test', (WidgetTester tester) async {
    final JumperSdkPlatform plugin = JumperSdkPlatform();
    final String? version = await plugin.getPlatformVersion();
    expect(version?.isNotEmpty, true);
  });

  testWidgets('native start/stop/restart uses real runtime mode', (
    WidgetTester tester,
  ) async {
    if (!Platform.isLinux && !Platform.isWindows) {
      return;
    }

    final plugin = JumperSdkPlatform();
    final launchOptions = Platform.isWindows
        ? <String, Object?>{
            'binaryPath': r'C:\Windows\System32\cmd.exe',
            'arguments': <String>['/C', 'timeout /T 30 >NUL'],
            'workingDirectory': r'C:\Windows\System32',
          }
        : <String, Object?>{
            'binaryPath': '/bin/sh',
            'arguments': <String>['-c', 'sleep 30'],
            'workingDirectory': '/tmp',
          };

    try {
      await plugin.startCore(
        profileId: 'integration-test',
        launchOptions: launchOptions,
        networkMode: 'tunnel',
      );
      final started = await plugin.getCoreState();
      expect(started['status'], 'running');
      expect(started['runtimeMode'], 'real');

      await plugin.restartCore(reason: 'integration-restart');
      final restarted = await plugin.getCoreState();
      expect(restarted['status'], 'running');
      expect(restarted['runtimeMode'], 'real');
    } finally {
      await plugin.stopCore();
    }

    final stopped = await plugin.getCoreState();
    expect(stopped['status'], 'stopped');
  });

  testWidgets('setupRuntime and inspectRuntime are available on native plugins', (
    WidgetTester tester,
  ) async {
    if (!Platform.isLinux && !Platform.isWindows) {
      return;
    }
    if (_workspaceBasePath.isEmpty) {
      fail('JUMPER_WORKSPACE_BASE_PATH is required');
    }

    final plugin = JumperSdkPlatform();
    final platformArch = Platform.isWindows ? 'windows-amd64' : 'linux-amd64';
    final setup = await plugin.setupRuntime(
      version: _runtimeVersion,
      platformArch: platformArch,
      basePath: _workspaceBasePath,
    );
    expect(setup['installed'], true);

    final inspect = await plugin.inspectRuntime(
      version: _runtimeVersion,
      platformArch: platformArch,
      basePath: _workspaceBasePath,
    );
    expect(inspect['ready'], true);
    expect(inspect['binaryExists'], true);
    expect(inspect['configExists'], true);
    expect(inspect['versionMatches'], true);
  });
}
