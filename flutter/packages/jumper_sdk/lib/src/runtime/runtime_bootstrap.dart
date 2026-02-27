import 'dart:convert';
import 'dart:io';

import '../models/sdk_models.dart';

const kDefaultCoreBasePath = 'data/sing-box';

class JumperRuntimeLayout {
  const JumperRuntimeLayout({
    required this.appBasePath,
    required this.coreBasePath,
    required this.coreWorkingDirectory,
    required this.coreConfigFilePath,
    required this.corePidFilePath,
    required this.coreBinaryPath,
  });

  final String appBasePath;
  final String coreBasePath;
  final String coreWorkingDirectory;
  final String coreConfigFilePath;
  final String corePidFilePath;
  final String coreBinaryPath;
}

class JumperRuntimeBootstrap {
  const JumperRuntimeBootstrap._();

  static JumperRuntimeLayout resolveLayout({
    required String appBasePath,
    String coreBasePath = kDefaultCoreBasePath,
    String? coreBinaryName,
  }) {
    final binaryName =
        coreBinaryName ?? (Platform.isWindows ? 'sing-box.exe' : 'sing-box');
    final workingDirectory = _joinPath(appBasePath, coreBasePath);
    final configPath = _joinPath(workingDirectory, 'config.json');
    final pidPath = _joinPath(workingDirectory, 'pid.txt');
    final binaryPath = _joinPath(workingDirectory, binaryName);

    return JumperRuntimeLayout(
      appBasePath: appBasePath,
      coreBasePath: coreBasePath,
      coreWorkingDirectory: workingDirectory,
      coreConfigFilePath: configPath,
      corePidFilePath: pidPath,
      coreBinaryPath: binaryPath,
    );
  }

  static Future<JumperRuntimeLaunchOptions> prepareLaunchOptions({
    required String appBasePath,
    required Map<String, Object?> config,
    String coreBasePath = kDefaultCoreBasePath,
    String? coreBinaryName,
    List<String>? arguments,
    Map<String, String> environment = const <String, String>{},
  }) async {
    final layout = resolveLayout(
      appBasePath: appBasePath,
      coreBasePath: coreBasePath,
      coreBinaryName: coreBinaryName,
    );

    await Directory(layout.coreWorkingDirectory).create(recursive: true);
    await File(layout.coreConfigFilePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );

    final launchArgs =
        arguments ??
        <String>[
          'run',
          '--disable-color',
          '-c',
          layout.coreConfigFilePath,
          '-D',
          layout.coreWorkingDirectory,
        ];

    return JumperRuntimeLaunchOptions(
      binaryPath: layout.coreBinaryPath,
      arguments: launchArgs,
      workingDirectory: layout.coreWorkingDirectory,
      environment: environment,
    );
  }

  static String _joinPath(String left, String right) {
    final separator = Platform.pathSeparator;
    final normalizedLeft =
        left.endsWith(separator) ? left.substring(0, left.length - 1) : left;
    final normalizedRight =
        right.startsWith(separator) ? right.substring(1) : right;
    return '$normalizedLeft$separator$normalizedRight';
  }
}
