import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jumper_sdk/jumper_sdk.dart';

const _coreBinaryPath = String.fromEnvironment('JUMPER_CORE_BIN', defaultValue: '');
const _coreArguments = String.fromEnvironment('JUMPER_CORE_ARGS', defaultValue: '');
const _coreWorkingDirectory = String.fromEnvironment('JUMPER_CORE_WORKDIR', defaultValue: '');
const _coreApiBase = String.fromEnvironment('JUMPER_CORE_API_BASE', defaultValue: 'http://127.0.0.1:20123');
const _coreApiSecret = String.fromEnvironment('JUMPER_CORE_API_SECRET', defaultValue: '');
const _appBasePath = String.fromEnvironment('JUMPER_APP_BASE_PATH', defaultValue: '');
const _coreBasePath = String.fromEnvironment('JUMPER_CORE_BASE_PATH', defaultValue: 'data/sing-box');
const _coreConfigJson = String.fromEnvironment('JUMPER_CORE_CONFIG_JSON', defaultValue: '');

const kStartButtonKey = Key('smoke.start');
const kStopButtonKey = Key('smoke.stop');
const kRestartButtonKey = Key('smoke.restart');
const kLoadProxiesButtonKey = Key('smoke.loadProxies');
const kProxyCountTextKey = Key('smoke.proxyCount');
const kRuntimeModeTextKey = Key('smoke.runtimeMode');

void main() {
  runApp(const SmokeApp());
}

class SmokeApp extends StatelessWidget {
  const SmokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jumper SDK Smoke',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
      home: const SmokeHomePage(),
    );
  }
}

class SmokeHomePage extends StatefulWidget {
  const SmokeHomePage({super.key});

  @override
  State<SmokeHomePage> createState() => _SmokeHomePageState();
}

class _SmokeHomePageState extends State<SmokeHomePage> {
  JumperSdkClient? _sdk;
  final List<String> _events = <String>[];
  final List<String> _logs = <String>[];
  final List<String> _proxyGroups = <String>[];

  StreamSubscription<CoreEvent>? _coreSubscription;
  StreamSubscription<KernelLogEvent>? _logSubscription;
  CoreState _state = const CoreState(status: CoreStatus.stopped);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initSdk();
  }

  @override
  void dispose() {
    _coreSubscription?.cancel();
    _logSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshState() async {
    final sdk = _sdk;
    if (sdk == null) {
      return;
    }
    final state = await sdk.getState();
    if (!mounted) {
      return;
    }
    setState(() {
      _state = state;
    });
  }

  Future<void> _start() async {
    await _runSafely(() async {
      final sdk = _sdk;
      if (sdk == null) {
        throw const JumperSdkException('SDK-INIT-001', 'SDK is not initialized');
      }
      await sdk.startCore(profileId: 'smoke-profile');
      await _refreshState();
    });
  }

  Future<void> _stop() async {
    await _runSafely(() async {
      final sdk = _sdk;
      if (sdk == null) {
        throw const JumperSdkException('SDK-INIT-001', 'SDK is not initialized');
      }
      await sdk.stopCore();
      await _refreshState();
    });
  }

  Future<void> _restart() async {
    await _runSafely(() async {
      final sdk = _sdk;
      if (sdk == null) {
        throw const JumperSdkException('SDK-INIT-001', 'SDK is not initialized');
      }
      await sdk.restartCore(reason: 'smoke-test');
      await _refreshState();
    });
  }

  Future<void> _runSafely(Future<void> Function() action) async {
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SDK error: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _loadProxies() async {
    await _runSafely(() async {
      final sdk = _sdk;
      if (sdk == null) {
        throw const JumperSdkException('SDK-INIT-001', 'SDK is not initialized');
      }
      final snapshot = await sdk.getProxies();
      setState(() {
        _proxyGroups
          ..clear()
          ..addAll(snapshot.groups.keys);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jumper SDK Smoke')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${_state.status.name}'),
            Text('PID: ${_state.pid?.toString() ?? '-'}'),
            Text(
              'Runtime mode: ${_state.runtimeMode ?? 'unknown'}',
              key: kRuntimeModeTextKey,
            ),
            Text('Message: ${_state.message ?? '-'}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  key: kStartButtonKey,
                  onPressed: _busy || _sdk == null ? null : _start,
                  child: const Text('Start'),
                ),
                ElevatedButton(
                  key: kStopButtonKey,
                  onPressed: _busy || _sdk == null ? null : _stop,
                  child: const Text('Stop'),
                ),
                ElevatedButton(
                  key: kRestartButtonKey,
                  onPressed: _busy || _sdk == null ? null : _restart,
                  child: const Text('Restart'),
                ),
                OutlinedButton(
                  onPressed: _busy || _sdk == null ? null : _refreshState,
                  child: const Text('Refresh State'),
                ),
                OutlinedButton(
                  key: kLoadProxiesButtonKey,
                  onPressed: _busy || _sdk == null ? null : _loadProxies,
                  child: const Text('Load Proxies'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Proxy groups loaded: ${_proxyGroups.length}', key: kProxyCountTextKey),
            const SizedBox(height: 16),
            const Text('Core Events'),
            Expanded(
              child: ListView(
                children: _events.map((value) => Text(value)).toList(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Kernel Logs'),
            Expanded(
              child: ListView(
                children: _logs.map((value) => Text(value)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initSdk() async {
    try {
      final client = await _buildSdkClient();
      if (!mounted) {
        return;
      }
      setState(() {
        _sdk = client;
      });

      _coreSubscription = client.watchCoreEvents().listen((event) {
        setState(() {
          _events.insert(0, '${event.type} ${event.payload}');
          if (_events.length > 20) {
            _events.removeLast();
          }
        });
        _refreshState();
      });

      _logSubscription = client.watchLogs().listen((event) {
        setState(() {
          _logs.insert(0, '[${event.level}] ${event.message}');
          if (_logs.length > 20) {
            _logs.removeLast();
          }
        });
      });
      _refreshState();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('SDK init error: $error')));
    }
  }
}

Future<JumperSdkClient> _buildSdkClient() async {
  final hasLaunchConfig = _coreBinaryPath.isNotEmpty;
  JumperRuntimeLaunchOptions? launchOptions;

  if (hasLaunchConfig) {
    launchOptions = JumperRuntimeLaunchOptions(
      binaryPath: _coreBinaryPath,
      arguments: _splitArgs(_coreArguments),
      workingDirectory: _coreWorkingDirectory.isEmpty ? null : _coreWorkingDirectory,
    );
  } else if (_appBasePath.isNotEmpty && _coreConfigJson.isNotEmpty) {
    final decoded = jsonDecode(_coreConfigJson);
    if (decoded is Map) {
      launchOptions = await JumperRuntimeBootstrap.prepareLaunchOptions(
        appBasePath: _appBasePath,
        coreBasePath: _coreBasePath,
        config: decoded.cast<String, Object?>(),
      );
    } else {
      throw const JumperSdkException(
        'SDK-INIT-002',
        'JUMPER_CORE_CONFIG_JSON must be a JSON object',
      );
    }
  } else if (_appBasePath.isNotEmpty) {
    final layout = JumperRuntimeBootstrap.resolveLayout(
      appBasePath: _appBasePath,
      coreBasePath: _coreBasePath,
    );
    if (File(layout.coreConfigFilePath).existsSync()) {
      launchOptions = JumperRuntimeLaunchOptions(
        binaryPath: layout.coreBinaryPath,
        arguments: <String>[
          'run',
          '--disable-color',
          '-c',
          layout.coreConfigFilePath,
          '-D',
          layout.coreWorkingDirectory,
        ],
        workingDirectory: layout.coreWorkingDirectory,
      );
    }
  }

  return JumperSdkClient(
    runtimeLaunchOptions: launchOptions,
    coreApiBaseUri: Uri.parse(_coreApiBase),
    coreApiSecret: _coreApiSecret.isEmpty ? null : _coreApiSecret,
  );
}

List<String> _splitArgs(String args) {
  return args
      .split(' ')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}
