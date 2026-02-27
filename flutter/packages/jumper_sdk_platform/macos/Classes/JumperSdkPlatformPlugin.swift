import Cocoa
import FlutterMacOS
import UserNotifications

public class JumperSdkPlatformPlugin: NSObject, FlutterPlugin {
  private static let runtimeManifestRelativePath = "engine/runtime-assets/manifest.json"
  private static let runtimeAssetsRelativePath = "engine/runtime-assets"

  private struct LaunchOptions {
    let binaryPath: String
    let arguments: [String]
    let workingDirectory: String?
    let environment: [String: String]
  }

  private var coreState: String = "stopped"
  private var corePid: Int64?
  private var runtimeMode: String = "simulator"
  private var networkMode: String = "tunnel"
  private var lastProfileId: String?
  private var lastStartArguments: [String: Any] = [:]
  private var pendingStopCompletions: [() -> Void] = []
  private var coreEventSink: FlutterEventSink?
  private var kernelLogSink: FlutterEventSink?
  private var coreProcess: Process?
  private var stdoutPipe: Pipe?
  private var stderrPipe: Pipe?
  private var logTimer: DispatchSourceTimer?
  private var trayStatusItem: NSStatusItem?
  private var trayTitle: String?
  private let proxySnapshotFileName = "system-proxy-snapshot.json"

  private final class EventStreamHandler: NSObject, FlutterStreamHandler {
    var onListenHandler: ((FlutterEventSink?) -> Void)?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
      onListenHandler?(events)
      return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
      onListenHandler?(nil)
      return nil
    }
  }

  private let coreEventsHandler = EventStreamHandler()
  private let kernelLogsHandler = EventStreamHandler()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "jumper_sdk_platform", binaryMessenger: registrar.messenger)
    let instance = JumperSdkPlatformPlugin()
    let coreEventsChannel = FlutterEventChannel(
      name: "jumper_sdk_platform/core_events",
      binaryMessenger: registrar.messenger
    )
    let kernelLogsChannel = FlutterEventChannel(
      name: "jumper_sdk_platform/kernel_logs",
      binaryMessenger: registrar.messenger
    )

    instance.coreEventsHandler.onListenHandler = { sink in
      instance.coreEventSink = sink
    }
    instance.kernelLogsHandler.onListenHandler = { sink in
      instance.kernelLogSink = sink
    }

    coreEventsChannel.setStreamHandler(instance.coreEventsHandler)
    kernelLogsChannel.setStreamHandler(instance.kernelLogsHandler)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "startCore":
      startCore(call: call, result: result)
    case "stopCore":
      stopCore(result: result)
    case "restartCore":
      restartCore(call: call, result: result)
    case "resetTunnel":
      resetTunnel(result: result)
    case "getCoreState":
      result(currentStateMap())
    case "setupRuntime":
      setupRuntime(call: call, result: result)
    case "inspectRuntime":
      inspectRuntime(call: call, result: result)
    case "enableSystemProxy":
      enableSystemProxy(call: call, result: result)
    case "disableSystemProxy":
      disableSystemProxy(result: result)
    case "getSystemProxyStatus":
      getSystemProxyStatus(result: result)
    case "requestNotificationPermission":
      requestNotificationPermission(result: result)
    case "getNotificationPermissionStatus":
      getNotificationPermissionStatus(result: result)
    case "showNotification":
      showNotification(call: call, result: result)
    case "showTray":
      showTray(call: call, result: result)
    case "updateTray":
      updateTray(call: call, result: result)
    case "hideTray":
      hideTray(result: result)
    case "getTrayStatus":
      getTrayStatus(result: result)
    case "getPlatformCapabilities":
      getPlatformCapabilities(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setupRuntime(call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      let request = try parseRuntimeRequest(call, requireBasePath: true)
      guard let basePath = request.basePath else {
        throw NSError(domain: "jumper.runtime", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing basePath"])
      }
      let metadata = try loadRuntimeMetadata(
        basePath: basePath,
        platformArch: request.platformArch,
        expectedVersion: request.version
      )
      let containerRuntimeRoot = runtimeContainerRoot()
      try FileManager.default.createDirectory(
        atPath: containerRuntimeRoot,
        withIntermediateDirectories: true
      )

      let sourceBinary = metadata.binaryPath
      let sourceConfig = basePath + "/engine/runtime-assets/\(request.platformArch)/minimal-config.json"
      let targetBinary = containerRuntimeRoot + "/sing-box"
      let targetConfig = containerRuntimeRoot + "/config.json"
      let targetVersion = containerRuntimeRoot + "/VERSION"

      try copyFile(source: sourceBinary, destination: targetBinary)
      guard FileManager.default.fileExists(atPath: sourceConfig) else {
        throw NSError(
          domain: "jumper.runtime",
          code: 8,
          userInfo: [NSLocalizedDescriptionKey: "Source config not found: \(sourceConfig)"]
        )
      }
      try copyFile(source: sourceConfig, destination: targetConfig)
      try setExecutable(targetBinary)
      try request.version.write(
        to: URL(fileURLWithPath: targetVersion),
        atomically: true,
        encoding: .utf8
      )

      result([
        "installed": true,
        "binaryPath": targetBinary,
        "configPath": targetConfig,
        "runtimeRoot": containerRuntimeRoot
      ])
    } catch {
      result(
        FlutterError(
          code: "SETUP_RUNTIME_FAILED",
          message: "Failed to setup runtime in container",
          details: "\(error)"
        )
      )
    }
  }

  private func inspectRuntime(call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      let request = try parseRuntimeRequest(call, requireBasePath: false)
      let containerRuntimeRoot = runtimeContainerRoot()
      let binaryPath = containerRuntimeRoot + "/sing-box"
      let configPath = containerRuntimeRoot + "/config.json"
      let versionPath = containerRuntimeRoot + "/VERSION"
      let binaryExists = FileManager.default.fileExists(atPath: binaryPath)
      let configExists = FileManager.default.fileExists(atPath: configPath)
      let runtimeVersion = try? String(contentsOf: URL(fileURLWithPath: versionPath), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let versionMatches = runtimeVersion == request.version

      result([
        "ready": binaryExists && configExists && versionMatches,
        "binaryPath": binaryPath,
        "configPath": configPath,
        "binaryExists": binaryExists,
        "configExists": configExists,
        "runtimeVersion": runtimeVersion ?? "",
        "expectedVersion": request.version,
        "versionMatches": versionMatches
      ])
    } catch {
      result(
        FlutterError(
          code: "INSPECT_RUNTIME_FAILED",
          message: "Failed to inspect runtime",
          details: "\(error)"
        )
      )
    }
  }

  private func enableSystemProxy(call: FlutterMethodCall, result: @escaping FlutterResult) {
    var services: [String] = []
    do {
      guard let args = call.arguments as? [String: Any] else {
        throw NSError(
          domain: "jumper.proxy",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Missing arguments"]
        )
      }
      guard let host = args["host"] as? String, !host.isEmpty else {
        throw NSError(
          domain: "jumper.proxy",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Missing host"]
        )
      }
      guard let port = args["port"] as? Int, port > 0 else {
        throw NSError(
          domain: "jumper.proxy",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Invalid port"]
        )
      }

      services = try listNetworkServices()
      if try loadProxySnapshot() == nil {
        try saveCurrentProxySnapshot(services: services)
      }
      for service in services {
        try runNetworksetup(["-setwebproxy", service, host, "\(port)"])
        try runNetworksetup(["-setwebproxystate", service, "on"])
        try runNetworksetup(["-setsecurewebproxy", service, host, "\(port)"])
        try runNetworksetup(["-setsecurewebproxystate", service, "on"])
        try runNetworksetup(["-setsocksfirewallproxy", service, host, "\(port)"])
        try runNetworksetup(["-setsocksfirewallproxystate", service, "on"])
      }
      result(nil)
    } catch {
      var restoreErrorText: String?
      do {
        if let snapshot = try loadProxySnapshot(), !services.isEmpty {
          try restoreProxySnapshot(snapshot, services: services)
        }
      } catch {
        restoreErrorText = "\(error)"
      }
      result(
        FlutterError(
          code: "SYSTEM_PROXY_ENABLE_FAILED",
          message: "Failed to enable system proxy",
          details: [
            "error": "\(error)",
            "rollback": restoreErrorText ?? "ok"
          ]
        )
      )
    }
  }

  private func disableSystemProxy(result: @escaping FlutterResult) {
    do {
      let services = try listNetworkServices()
      if let snapshot = try loadProxySnapshot() {
        try restoreProxySnapshot(snapshot, services: services)
      } else {
        for service in services {
          try runNetworksetup(["-setwebproxystate", service, "off"])
          try runNetworksetup(["-setsecurewebproxystate", service, "off"])
          try runNetworksetup(["-setsocksfirewallproxystate", service, "off"])
        }
      }
      try removeProxySnapshot()
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "SYSTEM_PROXY_DISABLE_FAILED",
          message: "Failed to disable system proxy",
          details: "\(error)"
        )
      )
    }
  }

  private func getSystemProxyStatus(result: @escaping FlutterResult) {
    do {
      let services = try listNetworkServices()
      for service in services {
        let socksOutput = try runNetworksetup(["-getsocksfirewallproxy", service])
        if let socks = parseProxyStatusOutput(socksOutput), socks.enabled {
          result([
            "enabled": true,
            "host": socks.host ?? "",
            "port": socks.port ?? 0,
            "service": service,
            "mode": "socks"
          ])
          return
        }

        let webOutput = try runNetworksetup(["-getwebproxy", service])
        if let web = parseProxyStatusOutput(webOutput), web.enabled {
          result([
            "enabled": true,
            "host": web.host ?? "",
            "port": web.port ?? 0,
            "service": service,
            "mode": "http"
          ])
          return
        }
      }
      result([
        "enabled": false
      ])
    } catch {
      result(
        FlutterError(
          code: "SYSTEM_PROXY_STATUS_FAILED",
          message: "Failed to query system proxy status",
          details: "\(error)"
        )
      )
    }
  }

  private func requestNotificationPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
      granted,
      error in
      if let error {
        result(
          FlutterError(
            code: "NOTIFY_PERMISSION_REQUEST_FAILED",
            message: "Failed to request notification permission",
            details: "\(error)"
          )
        )
        return
      }
      result(granted)
    }
  }

  private func getNotificationPermissionStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let status = settings.authorizationStatus
      let granted = status == .authorized || status == .provisional
      result(granted)
    }
  }

  private func showNotification(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let title = args["title"] as? String, !title.isEmpty,
      let body = args["body"] as? String else {
      result(
        FlutterError(
          code: "NOTIFY_INVALID_ARGUMENTS",
          message: "showNotification requires non-empty title and body",
          details: nil
        )
      )
      return
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = UNNotificationSound.default

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        result(
          FlutterError(
            code: "NOTIFY_SEND_FAILED",
            message: "Failed to send notification",
            details: "\(error)"
          )
        )
        return
      }
      result(nil)
    }
  }

  private func showTray(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let title = args["title"] as? String, !title.isEmpty else {
      result(
        FlutterError(
          code: "TRAY_INVALID_ARGUMENTS",
          message: "showTray requires non-empty title",
          details: nil
        )
      )
      return
    }
    let tooltip = args["tooltip"] as? String

    DispatchQueue.main.async {
      if self.trayStatusItem == nil {
        self.trayStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      }
      self.trayStatusItem?.button?.title = title
      self.trayStatusItem?.button?.toolTip = tooltip
      self.trayTitle = title
      result(nil)
    }
  }

  private func updateTray(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let title = args["title"] as? String, !title.isEmpty else {
      result(
        FlutterError(
          code: "TRAY_INVALID_ARGUMENTS",
          message: "updateTray requires non-empty title",
          details: nil
        )
      )
      return
    }
    let tooltip = args["tooltip"] as? String

    DispatchQueue.main.async {
      if self.trayStatusItem == nil {
        self.trayStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      }
      self.trayStatusItem?.button?.title = title
      self.trayStatusItem?.button?.toolTip = tooltip
      self.trayTitle = title
      result(nil)
    }
  }

  private func hideTray(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      if let item = self.trayStatusItem {
        NSStatusBar.system.removeStatusItem(item)
      }
      self.trayStatusItem = nil
      self.trayTitle = nil
      result(nil)
    }
  }

  private func getTrayStatus(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      result([
        "visible": self.trayStatusItem != nil,
        "title": self.trayTitle ?? ""
      ])
    }
  }

  private func getPlatformCapabilities(result: @escaping FlutterResult) {
    result([
      "tunnelSupported": true,
      "systemProxySupported": true,
      "notifySupported": true,
      "traySupported": true
    ])
  }

  private struct RuntimeRequest {
    let version: String
    let platformArch: String
    let basePath: String?
  }

  private func parseRuntimeRequest(
    _ call: FlutterMethodCall,
    requireBasePath: Bool
  ) throws -> RuntimeRequest {
    guard let args = call.arguments as? [String: Any] else {
      throw NSError(domain: "jumper.runtime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing arguments"])
    }
    guard let version = args["version"] as? String, !version.isEmpty else {
      throw NSError(domain: "jumper.runtime", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing version"])
    }
    guard let platformArch = args["platformArch"] as? String, !platformArch.isEmpty else {
      throw NSError(domain: "jumper.runtime", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing platformArch"])
    }
    let basePath = args["basePath"] as? String
    if requireBasePath && (basePath == nil || basePath?.isEmpty == true) {
      throw NSError(domain: "jumper.runtime", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing basePath"])
    }
    return RuntimeRequest(version: version, platformArch: platformArch, basePath: basePath)
  }

  private struct RuntimeMetadata {
    let manifestVersion: String
    let binaryPath: String
  }

  private func loadRuntimeMetadata(
    basePath: String,
    platformArch: String,
    expectedVersion: String
  ) throws -> RuntimeMetadata {
    let manifestPath = basePath + "/" + Self.runtimeManifestRelativePath
    let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let singBox = json["sing_box"] as? [String: Any],
          let manifestVersion = singBox["version"] as? String,
          let assets = singBox["assets"] as? [String: Any],
          let platformInfo = assets[platformArch] as? [String: Any],
          let relativeBinaryPath = platformInfo["binary_relative_path"] as? String
    else {
      throw NSError(domain: "jumper.runtime", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid manifest format"])
    }
    if manifestVersion != expectedVersion {
      throw NSError(
        domain: "jumper.runtime",
        code: 7,
        userInfo: [NSLocalizedDescriptionKey: "Version mismatch: expected=\(expectedVersion) manifest=\(manifestVersion)"]
      )
    }
    let binaryPath = basePath + "/" + Self.runtimeAssetsRelativePath + "/" + platformArch + "/" + relativeBinaryPath
    if !FileManager.default.fileExists(atPath: binaryPath) {
      throw NSError(domain: "jumper.runtime", code: 6, userInfo: [NSLocalizedDescriptionKey: "Runtime binary not found: \(binaryPath)"])
    }
    return RuntimeMetadata(manifestVersion: manifestVersion, binaryPath: binaryPath)
  }

  private func runtimeContainerRoot() -> String {
    return NSHomeDirectory() + "/Library/Application Support/jumper-runtime"
  }

  private func copyFile(source: String, destination: String) throws {
    if FileManager.default.fileExists(atPath: destination) {
      try FileManager.default.removeItem(atPath: destination)
    }
    try FileManager.default.copyItem(atPath: source, toPath: destination)
  }

  private func setExecutable(_ path: String) throws {
    let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: Int16(0o755))]
    try FileManager.default.setAttributes(attrs, ofItemAtPath: path)
  }

  private func startCore(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if coreState == "running" || coreState == "starting" {
      result(nil)
      return
    }

    let args = call.arguments as? [String: Any] ?? [:]
    lastStartArguments = args
    lastProfileId = args["profileId"] as? String
    if let requestedMode = args["networkMode"] as? String, !requestedMode.isEmpty {
      networkMode = requestedMode
    }

    if let launchOptions = parseLaunchOptions(args) {
      startRealCore(launchOptions, result: result)
      return
    }

    runtimeMode = "simulator"
    transitionState(to: "starting", message: "core is starting")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      self.corePid = Int64(ProcessInfo.processInfo.processIdentifier) + Int64(Int.random(in: 100...999))
      self.transitionState(to: "running", message: "core started")
      self.startLogEmitter()
      result(nil)
    }
  }

  private func stopCore(result: @escaping FlutterResult) {
    stopCoreInternal {
      result(nil)
    }
  }

  private func restartCore(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let patch = call.arguments as? [String: Any] ?? [:]
    let nextArgs = mergeStartArguments(patch)
    let nextCall = FlutterMethodCall(methodName: "startCore", arguments: nextArgs)
    stopCoreInternal { [weak self] in
      guard let self else { return }
      self.startCore(call: nextCall, result: result)
    }
  }

  private func transitionState(to next: String, message: String) {
    coreState = next
    coreEventSink?([
      "type": "core_state_changed",
      "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
      "payload": currentStateMap().merging(["message": message]) { _, new in new }
    ])
  }

  private func currentStateMap() -> [String: Any] {
    var map: [String: Any] = [
      "status": coreState,
      "profileId": lastProfileId ?? "",
      "runtimeMode": runtimeMode,
      "networkMode": networkMode,
    ]
    if let corePid {
      map["pid"] = corePid
    }
    return map
  }

  private func parseLaunchOptions(_ args: [String: Any]) -> LaunchOptions? {
    guard let rawLaunch = args["launchOptions"] as? [String: Any] else {
      return nil
    }
    guard let binaryPath = rawLaunch["binaryPath"] as? String, !binaryPath.isEmpty else {
      return nil
    }
    let arguments = rawLaunch["arguments"] as? [String] ?? []
    let workingDirectory = rawLaunch["workingDirectory"] as? String
    let rawEnvironment = rawLaunch["environment"] as? [String: Any] ?? [:]
    var environment: [String: String] = [:]
    rawEnvironment.forEach { key, value in
      if let text = value as? String {
        environment[key] = text
      }
    }
    return LaunchOptions(
      binaryPath: binaryPath,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment
    )
  }

  private func resetTunnel(result: @escaping FlutterResult) {
    if coreState != "running" {
      result(nil)
      return
    }
    let resetCall = FlutterMethodCall(methodName: "restartCore", arguments: [
      "reason": "reset_tunnel",
      "networkMode": "tunnel"
    ])
    restartCore(call: resetCall, result: result)
  }

  private struct ProxySnapshot: Codable {
    var services: [String: ServiceProxySnapshot]
  }

  private struct ServiceProxySnapshot: Codable {
    var web: ProxyState
    var secureweb: ProxyState
    var socks: ProxyState
  }

  private struct ProxyState: Codable {
    var enabled: Bool
    var host: String?
    var port: Int?
  }

  private func proxySnapshotPath() -> String {
    return runtimeContainerRoot() + "/" + proxySnapshotFileName
  }

  private func saveCurrentProxySnapshot(services: [String]) throws {
    var snapshot = ProxySnapshot(services: [:])
    for service in services {
      let web = parseProxyStatusOutput(try runNetworksetup(["-getwebproxy", service])) ?? ProxyStatusParsed(
        enabled: false,
        host: nil,
        port: nil
      )
      let secure = parseProxyStatusOutput(try runNetworksetup(["-getsecurewebproxy", service])) ?? ProxyStatusParsed(
        enabled: false,
        host: nil,
        port: nil
      )
      let socks = parseProxyStatusOutput(try runNetworksetup(["-getsocksfirewallproxy", service])) ?? ProxyStatusParsed(
        enabled: false,
        host: nil,
        port: nil
      )
      snapshot.services[service] = ServiceProxySnapshot(
        web: ProxyState(enabled: web.enabled, host: web.host, port: web.port),
        secureweb: ProxyState(enabled: secure.enabled, host: secure.host, port: secure.port),
        socks: ProxyState(enabled: socks.enabled, host: socks.host, port: socks.port)
      )
    }
    let data = try JSONEncoder().encode(snapshot)
    let path = proxySnapshotPath()
    let dir = (path as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  private func loadProxySnapshot() throws -> ProxySnapshot? {
    let path = proxySnapshotPath()
    if !FileManager.default.fileExists(atPath: path) {
      return nil
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(ProxySnapshot.self, from: data)
  }

  private func removeProxySnapshot() throws {
    let path = proxySnapshotPath()
    if FileManager.default.fileExists(atPath: path) {
      try FileManager.default.removeItem(atPath: path)
    }
  }

  private func restoreProxySnapshot(_ snapshot: ProxySnapshot, services: [String]) throws {
    for service in services {
      guard let entry = snapshot.services[service] else {
        try runNetworksetup(["-setwebproxystate", service, "off"])
        try runNetworksetup(["-setsecurewebproxystate", service, "off"])
        try runNetworksetup(["-setsocksfirewallproxystate", service, "off"])
        continue
      }

      try applyProxyState(
        service: service,
        state: entry.web,
        setCommand: "-setwebproxy",
        stateCommand: "-setwebproxystate"
      )
      try applyProxyState(
        service: service,
        state: entry.secureweb,
        setCommand: "-setsecurewebproxy",
        stateCommand: "-setsecurewebproxystate"
      )
      try applyProxyState(
        service: service,
        state: entry.socks,
        setCommand: "-setsocksfirewallproxy",
        stateCommand: "-setsocksfirewallproxystate"
      )
    }
  }

  private func applyProxyState(
    service: String,
    state: ProxyState,
    setCommand: String,
    stateCommand: String
  ) throws {
    if state.enabled, let host = state.host, let port = state.port, port > 0 {
      try runNetworksetup([setCommand, service, host, "\(port)"])
      try runNetworksetup([stateCommand, service, "on"])
      return
    }
    try runNetworksetup([stateCommand, service, "off"])
  }

  private struct ProxyStatusParsed {
    let enabled: Bool
    let host: String?
    let port: Int?
  }

  private func parseProxyStatusOutput(_ output: String) -> ProxyStatusParsed? {
    var enabled = false
    var host: String?
    var port: Int?
    for rawLine in output.split(separator: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("Enabled:") {
        enabled = line.lowercased().contains("yes")
      } else if line.hasPrefix("Server:") {
        host = line.replacingOccurrences(of: "Server:", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
      } else if line.hasPrefix("Port:") {
        let portText = line.replacingOccurrences(of: "Port:", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        port = Int(portText)
      }
    }
    return ProxyStatusParsed(enabled: enabled, host: host, port: port)
  }

  private func listNetworkServices() throws -> [String] {
    let output = try runNetworksetup(["-listallnetworkservices"])
    return output.split(separator: "\n")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { line in
        !line.isEmpty
        && !line.hasPrefix("An asterisk")
        && !line.hasPrefix("*")
      }
  }

  @discardableResult
  private func runNetworksetup(_ args: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    process.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    try process.run()
    process.waitUntilExit()

    let stdoutData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

    if process.terminationStatus != 0 {
      throw NSError(
        domain: "jumper.proxy",
        code: Int(process.terminationStatus),
        userInfo: [
          NSLocalizedDescriptionKey: "networksetup failed: \(args.joined(separator: " "))",
          "stderr": stderr
        ]
      )
    }
    return stdout
  }

  private func startRealCore(_ launchOptions: LaunchOptions, result: @escaping FlutterResult) {
    stopLogEmitter()
    cleanupRealProcessState()

    if isAppSandboxEnabled(), !isPathInsideAppContainer(launchOptions.binaryPath) {
      transitionState(to: "error", message: "runtime path is blocked by app sandbox")
      result(
        FlutterError(
          code: "RUNTIME_PATH_BLOCKED_BY_SANDBOX",
          message: "In sandbox mode, runtime binary must be inside app container path",
          details: [
            "binaryPath": launchOptions.binaryPath,
            "containerRoot": NSHomeDirectory(),
            "hint": "Use external pre-start mode or place runtime inside app container."
          ]
        )
      )
      return
    }

    if networkMode == "tunnel", !isTunnelEnabledInLaunchConfig(launchOptions.arguments) {
      transitionState(to: "error", message: "tunnel mode requires tun-enabled config")
      result(
        FlutterError(
          code: "TUNNEL_CONFIG_NOT_ENABLED",
          message: "Network mode is tunnel, but launch config does not enable tun inbound",
          details: [
            "arguments": launchOptions.arguments
          ]
        )
      )
      return
    }

    transitionState(to: "starting", message: "core is starting (real runtime)")
    runtimeMode = "real"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchOptions.binaryPath)
    process.arguments = launchOptions.arguments
    if let workingDirectory = launchOptions.workingDirectory, !workingDirectory.isEmpty {
      process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
    }
    if !launchOptions.environment.isEmpty {
      var env = ProcessInfo.processInfo.environment
      launchOptions.environment.forEach { env[$0.key] = $0.value }
      process.environment = env
    }

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    process.terminationHandler = { [weak self] process in
      guard let self else { return }
      self.stopLogEmitter()
      self.cleanupRealProcessState()
      self.corePid = nil
      self.transitionState(to: "stopped", message: "core exited with status \(process.terminationStatus)")
      self.completePendingStopCompletions()
    }

    stdoutPipe = outPipe
    stderrPipe = errPipe
    coreProcess = process
    bindPipe(outPipe, level: "info")
    bindPipe(errPipe, level: "error")

    do {
      try process.run()
      corePid = Int64(process.processIdentifier)
      transitionState(to: "running", message: "core started (real runtime)")
      result(nil)
    } catch {
      cleanupRealProcessState()
      corePid = nil
      runtimeMode = "simulator"
      transitionState(to: "error", message: "core start failed")
      result(
        FlutterError(
          code: "START_CORE_FAILED",
          message: "Failed to start core process",
          details: "\(error)"
        )
      )
    }
  }

  private func bindPipe(_ pipe: Pipe, level: String) {
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      guard let self else { return }
      let data = handle.availableData
      if data.isEmpty {
        return
      }
      if let message = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
        self.kernelLogSink?([
          "level": level,
          "message": message,
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ])
      }
    }
  }

  private func startLogEmitter() {
    stopLogEmitter()
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now(), repeating: .seconds(1))
    timer.setEventHandler { [weak self] in
      guard let self, self.coreState == "running" else { return }
      self.kernelLogSink?([
        "level": "info",
        "message": "sdk runtime heartbeat",
        "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
      ])
    }
    timer.resume()
    logTimer = timer
  }

  private func stopLogEmitter() {
    logTimer?.cancel()
    logTimer = nil
  }

  private func cleanupRealProcessState() {
    stdoutPipe?.fileHandleForReading.readabilityHandler = nil
    stderrPipe?.fileHandleForReading.readabilityHandler = nil
    stdoutPipe = nil
    stderrPipe = nil
    coreProcess = nil
  }

  private func isTunnelEnabledInLaunchConfig(_ arguments: [String]) -> Bool {
    guard let configPath = resolveConfigPath(arguments) else {
      return false
    }
    guard let data = FileManager.default.contents(atPath: configPath),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let inbounds = json["inbounds"] as? [[String: Any]] else {
      return false
    }
    for inbound in inbounds {
      let type = (inbound["type"] as? String)?.lowercased()
      let enabled = (inbound["enable"] as? Bool) ?? true
      if type == "tun" && enabled {
        return true
      }
    }
    return false
  }

  private func resolveConfigPath(_ arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: "-c"), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }

  private func stopCoreInternal(_ completion: @escaping () -> Void) {
    if coreState == "stopped" || coreState == "stopping" {
      completion()
      return
    }

    transitionState(to: "stopping", message: "core is stopping")
    stopLogEmitter()
    if let process = coreProcess, process.isRunning {
      pendingStopCompletions.append(completion)
      process.terminate()
      return
    }
    cleanupRealProcessState()
    corePid = nil
    runtimeMode = "simulator"
    transitionState(to: "stopped", message: "core stopped")
    completion()
  }

  private func completePendingStopCompletions() {
    if pendingStopCompletions.isEmpty {
      return
    }
    let completions = pendingStopCompletions
    pendingStopCompletions.removeAll()
    completions.forEach { $0() }
  }

  private func mergeStartArguments(_ patch: [String: Any]) -> [String: Any] {
    var merged = lastStartArguments
    patch.forEach { key, value in
      merged[key] = value
    }
    if merged["networkMode"] == nil {
      merged["networkMode"] = networkMode
    }
    return merged
  }

  private func isAppSandboxEnabled() -> Bool {
    return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
  }

  private func isPathInsideAppContainer(_ path: String) -> Bool {
    let normalizedPath = URL(fileURLWithPath: path).standardized.path
    let normalizedHome = URL(fileURLWithPath: NSHomeDirectory()).standardized.path
    return normalizedPath.hasPrefix(normalizedHome + "/") || normalizedPath == normalizedHome
  }
}
