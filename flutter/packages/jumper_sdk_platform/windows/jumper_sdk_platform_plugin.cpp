#include "jumper_sdk_platform_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace jumper_sdk_platform {

namespace {
std::string QuoteWindowsArg(const std::string& arg) {
  if (arg.find_first_of(" \t\"") == std::string::npos) {
    return arg;
  }
  std::string out = "\"";
  for (const char c : arg) {
    if (c == '"') {
      out += "\\\"";
    } else {
      out += c;
    }
  }
  out += "\"";
  return out;
}
}  // namespace

// static
void JumperSdkPlatformPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "jumper_sdk_platform",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<JumperSdkPlatformPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

JumperSdkPlatformPlugin::JumperSdkPlatformPlugin() {}

JumperSdkPlatformPlugin::~JumperSdkPlatformPlugin() { StopRealCore(); }

bool JumperSdkPlatformPlugin::ParseLaunchOptions(
    const flutter::EncodableMap& args,
    LaunchOptions* options) {
  const auto launch_it = args.find(flutter::EncodableValue("launchOptions"));
  if (launch_it == args.end() ||
      !std::holds_alternative<flutter::EncodableMap>(launch_it->second)) {
    return false;
  }
  const auto& launch = std::get<flutter::EncodableMap>(launch_it->second);

  const auto binary_it = launch.find(flutter::EncodableValue("binaryPath"));
  if (binary_it == launch.end() ||
      !std::holds_alternative<std::string>(binary_it->second)) {
    return false;
  }
  options->binary_path = std::get<std::string>(binary_it->second);
  if (options->binary_path.empty()) {
    return false;
  }

  options->arguments.clear();
  const auto args_it = launch.find(flutter::EncodableValue("arguments"));
  if (args_it != launch.end() &&
      std::holds_alternative<flutter::EncodableList>(args_it->second)) {
    const auto& arg_list = std::get<flutter::EncodableList>(args_it->second);
    for (const auto& entry : arg_list) {
      if (std::holds_alternative<std::string>(entry)) {
        options->arguments.emplace_back(std::get<std::string>(entry));
      }
    }
  }

  options->working_directory.clear();
  const auto wd_it = launch.find(flutter::EncodableValue("workingDirectory"));
  if (wd_it != launch.end() && std::holds_alternative<std::string>(wd_it->second)) {
    options->working_directory = std::get<std::string>(wd_it->second);
  }
  return true;
}

bool JumperSdkPlatformPlugin::StartRealCore(const LaunchOptions& options, std::string* error) {
  StopRealCore();

  std::string cmdline = QuoteWindowsArg(options.binary_path);
  for (const auto& arg : options.arguments) {
    cmdline += " ";
    cmdline += QuoteWindowsArg(arg);
  }

  STARTUPINFOA startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  std::vector<char> mutable_cmdline(cmdline.begin(), cmdline.end());
  mutable_cmdline.push_back('\0');

  const char* cwd = options.working_directory.empty()
      ? nullptr
      : options.working_directory.c_str();
  const BOOL created = CreateProcessA(
      nullptr,
      mutable_cmdline.data(),
      nullptr,
      nullptr,
      FALSE,
      CREATE_NO_WINDOW,
      nullptr,
      cwd,
      &startup_info,
      &process_info);
  if (!created) {
    if (error != nullptr) {
      *error = "CreateProcess failed with code " + std::to_string(GetLastError());
    }
    return false;
  }

  process_info_ = process_info;
  has_real_process_ = true;
  pid_ = static_cast<int64_t>(process_info.dwProcessId);
  return true;
}

void JumperSdkPlatformPlugin::StopRealCore() {
  if (!has_real_process_) {
    return;
  }
  if (process_info_.hProcess != nullptr) {
    TerminateProcess(process_info_.hProcess, 0);
    WaitForSingleObject(process_info_.hProcess, 2000);
    CloseHandle(process_info_.hProcess);
    process_info_.hProcess = nullptr;
  }
  if (process_info_.hThread != nullptr) {
    CloseHandle(process_info_.hThread);
    process_info_.hThread = nullptr;
  }
  has_real_process_ = false;
}

void JumperSdkPlatformPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto get_string_arg = [&](const flutter::EncodableMap &args,
                                  const char *key) -> std::string {
    const auto it = args.find(flutter::EncodableValue(key));
    if (it != args.end() && std::holds_alternative<std::string>(it->second)) {
      return std::get<std::string>(it->second);
    }
    return "";
  };

  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  } else if (method_call.method_name().compare("startCore") == 0) {
    LaunchOptions launch_options;
    bool has_launch_options = false;
    if (method_call.arguments() != nullptr &&
        std::holds_alternative<flutter::EncodableMap>(*method_call.arguments())) {
      const auto &args = std::get<flutter::EncodableMap>(*method_call.arguments());
      const auto profile_id = get_string_arg(args, "profileId");
      if (!profile_id.empty()) {
        profile_id_ = profile_id;
      }
      const auto network_mode = get_string_arg(args, "networkMode");
      if (!network_mode.empty()) {
        network_mode_ = network_mode;
      }
      has_launch_options = ParseLaunchOptions(args, &launch_options);
    }
    if (has_launch_options) {
      std::string error;
      if (!StartRealCore(launch_options, &error)) {
        is_running_ = false;
        runtime_mode_ = "simulator";
        pid_ = 0;
        result->Error("START_CORE_FAILED", "Failed to start core process", error);
        return;
      }
      last_launch_options_ = launch_options;
      has_last_launch_options_ = true;
      runtime_mode_ = "real";
      is_running_ = true;
      result->Success();
      return;
    }

    is_running_ = true;
    runtime_mode_ = "simulator";
    pid_ = static_cast<int64_t>(::GetCurrentProcessId());
    result->Success();
  } else if (method_call.method_name().compare("stopCore") == 0) {
    StopRealCore();
    is_running_ = false;
    pid_ = 0;
    result->Success();
  } else if (method_call.method_name().compare("restartCore") == 0) {
    StopRealCore();
    LaunchOptions launch_options;
    bool has_launch_options = false;
    if (method_call.arguments() != nullptr &&
        std::holds_alternative<flutter::EncodableMap>(*method_call.arguments())) {
      const auto &args = std::get<flutter::EncodableMap>(*method_call.arguments());
      const auto network_mode = get_string_arg(args, "networkMode");
      if (!network_mode.empty()) {
        network_mode_ = network_mode;
      }
      has_launch_options = ParseLaunchOptions(args, &launch_options);
    }
    if (!has_launch_options && has_last_launch_options_) {
      launch_options = last_launch_options_;
      has_launch_options = true;
    }
    if (has_launch_options) {
      std::string error;
      if (!StartRealCore(launch_options, &error)) {
        is_running_ = false;
        runtime_mode_ = "simulator";
        pid_ = 0;
        result->Error("RESTART_CORE_FAILED", "Failed to restart core process", error);
        return;
      }
      last_launch_options_ = launch_options;
      has_last_launch_options_ = true;
      runtime_mode_ = "real";
      is_running_ = true;
      result->Success();
      return;
    }
    is_running_ = true;
    runtime_mode_ = "simulator";
    pid_ = static_cast<int64_t>(::GetCurrentProcessId());
    result->Success();
  } else if (method_call.method_name().compare("resetTunnel") == 0) {
    if (is_running_) {
      // Simulate a tunnel reset as a non-disruptive restart marker.
      pid_ = static_cast<int64_t>(::GetCurrentProcessId());
    }
    result->Success();
  } else if (method_call.method_name().compare("getCoreState") == 0) {
    flutter::EncodableMap state;
    state[flutter::EncodableValue("status")] =
        flutter::EncodableValue(is_running_ ? "running" : "stopped");
    state[flutter::EncodableValue("runtimeMode")] =
        flutter::EncodableValue(runtime_mode_);
    state[flutter::EncodableValue("networkMode")] =
        flutter::EncodableValue(network_mode_);
    if (pid_ > 0) {
      state[flutter::EncodableValue("pid")] = flutter::EncodableValue(pid_);
    }
    if (!profile_id_.empty()) {
      state[flutter::EncodableValue("profileId")] =
          flutter::EncodableValue(profile_id_);
    }
    result->Success(flutter::EncodableValue(state));
  } else if (method_call.method_name().compare("setupRuntime") == 0) {
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("installed")] = flutter::EncodableValue(false);
    payload[flutter::EncodableValue("ready")] = flutter::EncodableValue(false);
    payload[flutter::EncodableValue("platform")] = flutter::EncodableValue("windows");
    result->Success(flutter::EncodableValue(payload));
  } else if (method_call.method_name().compare("inspectRuntime") == 0) {
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("ready")] = flutter::EncodableValue(false);
    payload[flutter::EncodableValue("binaryExists")] = flutter::EncodableValue(false);
    payload[flutter::EncodableValue("configExists")] = flutter::EncodableValue(false);
    payload[flutter::EncodableValue("platform")] = flutter::EncodableValue("windows");
    result->Success(flutter::EncodableValue(payload));
  } else if (method_call.method_name().compare("enableSystemProxy") == 0 ||
             method_call.method_name().compare("disableSystemProxy") == 0 ||
             method_call.method_name().compare("requestNotificationPermission") == 0 ||
             method_call.method_name().compare("showNotification") == 0 ||
             method_call.method_name().compare("showTray") == 0 ||
             method_call.method_name().compare("updateTray") == 0 ||
             method_call.method_name().compare("hideTray") == 0) {
    result->Error(
        "PLATFORM_CAPABILITY_NOT_IMPLEMENTED",
        "Capability is not implemented on Windows plugin yet.",
        flutter::EncodableValue(method_call.method_name()));
  } else if (method_call.method_name().compare("getSystemProxyStatus") == 0) {
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("enabled")] = flutter::EncodableValue(false);
    payload[flutter::EncodableValue("platform")] = flutter::EncodableValue("windows");
    result->Success(flutter::EncodableValue(payload));
  } else if (method_call.method_name().compare("getNotificationPermissionStatus") == 0) {
    result->Success(flutter::EncodableValue(false));
  } else if (method_call.method_name().compare("getTrayStatus") == 0) {
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("visible")] = flutter::EncodableValue(false);
    payload[flutter::EncodableValue("title")] = flutter::EncodableValue("");
    result->Success(flutter::EncodableValue(payload));
  } else if (method_call.method_name().compare("getPlatformCapabilities") == 0) {
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("tunnelSupported")] = flutter::EncodableValue(true);
    payload[flutter::EncodableValue("systemProxySupported")] = flutter::EncodableValue(false);
    payload[flutter::EncodableValue("notifySupported")] = flutter::EncodableValue(false);
    payload[flutter::EncodableValue("traySupported")] = flutter::EncodableValue(false);
    result->Success(flutter::EncodableValue(payload));
  } else {
    result->NotImplemented();
  }
}

}  // namespace jumper_sdk_platform
