#include "jumper_sdk_platform_plugin.h"

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>
#include <shlobj.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <filesystem>
#include <fstream>
#include <memory>
#include <regex>
#include <sstream>
#include <string>
#include <thread>
#include <chrono>
#include <vector>
#include <cstdlib>
#include <algorithm>
#include <cctype>

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

std::string ToUpperAscii(std::string value) {
  std::transform(
      value.begin(),
      value.end(),
      value.begin(),
      [](unsigned char ch) { return static_cast<char>(std::toupper(ch)); });
  return value;
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
  options->environment.clear();
  const auto env_it = launch.find(flutter::EncodableValue("environment"));
  if (env_it != launch.end() &&
      std::holds_alternative<flutter::EncodableMap>(env_it->second)) {
    const auto& env_map = std::get<flutter::EncodableMap>(env_it->second);
    for (const auto& [key, value] : env_map) {
      if (!std::holds_alternative<std::string>(key) ||
          !std::holds_alternative<std::string>(value)) {
        continue;
      }
      options->environment.emplace(
          std::get<std::string>(key),
          std::get<std::string>(value));
    }
  }
  return true;
}

bool JumperSdkPlatformPlugin::ParseRuntimeRequest(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    bool require_base_path,
    RuntimeRequest* request,
    std::string* error) {
  if (method_call.arguments() == nullptr ||
      !std::holds_alternative<flutter::EncodableMap>(*method_call.arguments())) {
    if (error != nullptr) {
      *error = "Missing arguments";
    }
    return false;
  }
  const auto& args = std::get<flutter::EncodableMap>(*method_call.arguments());
  const auto get_string_arg = [&](const char* key) -> std::string {
    const auto it = args.find(flutter::EncodableValue(key));
    if (it != args.end() && std::holds_alternative<std::string>(it->second)) {
      return std::get<std::string>(it->second);
    }
    return "";
  };
  request->version = get_string_arg("version");
  request->platform_arch = get_string_arg("platformArch");
  request->base_path = get_string_arg("basePath");
  if (request->version.empty()) {
    if (error != nullptr) {
      *error = "Missing version";
    }
    return false;
  }
  if (request->platform_arch.empty()) {
    if (error != nullptr) {
      *error = "Missing platformArch";
    }
    return false;
  }
  if (require_base_path && request->base_path.empty()) {
    if (error != nullptr) {
      *error = "Missing basePath";
    }
    return false;
  }
  return true;
}

std::string JumperSdkPlatformPlugin::RuntimeContainerRoot() const {
  PWSTR app_data = nullptr;
  std::string root;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &app_data)) &&
      app_data != nullptr) {
    int size_needed =
        WideCharToMultiByte(CP_UTF8, 0, app_data, -1, nullptr, 0, nullptr, nullptr);
    if (size_needed > 0) {
      std::vector<char> utf8(size_needed);
      WideCharToMultiByte(CP_UTF8, 0, app_data, -1, utf8.data(), size_needed, nullptr, nullptr);
      root = std::string(utf8.data()) + "\\jumper-runtime";
    }
  }
  if (app_data != nullptr) {
    CoTaskMemFree(app_data);
  }
  if (root.empty()) {
    char* profile = nullptr;
    size_t profile_len = 0;
    if (_dupenv_s(&profile, &profile_len, "USERPROFILE") == 0 &&
        profile != nullptr &&
        profile_len > 1) {
      root = std::string(profile) + "\\AppData\\Roaming\\jumper-runtime";
    } else {
      root = ".\\jumper-runtime";
    }
    if (profile != nullptr) {
      free(profile);
    }
  }
  return root;
}

bool JumperSdkPlatformPlugin::EnsureDirectory(const std::string& path, std::string* error) const {
  try {
    std::filesystem::create_directories(std::filesystem::u8path(path));
    return true;
  } catch (const std::exception& ex) {
    if (error != nullptr) {
      *error = ex.what();
    }
    return false;
  }
}

bool JumperSdkPlatformPlugin::CopyFileReplace(
    const std::string& source,
    const std::string& destination,
    std::string* error) const {
  try {
    const auto source_path = std::filesystem::u8path(source);
    const auto destination_path = std::filesystem::u8path(destination);
    if (!std::filesystem::exists(source_path)) {
      if (error != nullptr) {
        *error = "Source file not found: " + source;
      }
      return false;
    }
    std::filesystem::create_directories(destination_path.parent_path());
    if (std::filesystem::exists(destination_path)) {
      std::filesystem::remove(destination_path);
    }
    std::filesystem::copy_file(source_path, destination_path);
    return true;
  } catch (const std::exception& ex) {
    if (error != nullptr) {
      *error = ex.what();
    }
    return false;
  }
}

bool JumperSdkPlatformPlugin::WriteTextFile(
    const std::string& path,
    const std::string& value,
    std::string* error) const {
  std::ofstream output(path, std::ios::trunc);
  if (!output.is_open()) {
    if (error != nullptr) {
      *error = "Unable to write file: " + path;
    }
    return false;
  }
  output << value;
  if (!output.good()) {
    if (error != nullptr) {
      *error = "Failed writing file: " + path;
    }
    return false;
  }
  return true;
}

bool JumperSdkPlatformPlugin::FileExists(const std::string& path) const {
  try {
    return std::filesystem::exists(std::filesystem::u8path(path));
  } catch (...) {
    return false;
  }
}

bool JumperSdkPlatformPlugin::IsTunnelEnabledInLaunchConfig(
    const std::vector<std::string>& arguments) const {
  std::string config_path;
  for (size_t i = 0; i < arguments.size(); ++i) {
    if (arguments[i] == "-c" && i + 1 < arguments.size()) {
      config_path = arguments[i + 1];
      break;
    }
  }
  if (config_path.empty()) {
    return false;
  }

  return IsTunInboundEnabledInConfig(config_path);
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
  std::vector<char> env_block;
  LPVOID environment = nullptr;
  std::unordered_map<std::string, std::pair<std::string, std::string>>
      merged_environment;
  LPCH current_env = GetEnvironmentStringsA();
  if (current_env != nullptr) {
    for (LPCSTR it = current_env; *it != '\0';) {
      const std::string entry(it);
      const size_t equal = entry.find('=');
      if (equal != std::string::npos && equal > 0) {
        const std::string key = entry.substr(0, equal);
        const std::string value = entry.substr(equal + 1);
        merged_environment[ToUpperAscii(key)] = std::make_pair(key, value);
      }
      it += entry.size() + 1;
    }
    FreeEnvironmentStringsA(current_env);
  }
  for (const auto& [key, value] : options.environment) {
    merged_environment[ToUpperAscii(key)] = std::make_pair(key, value);
  }
  if (!merged_environment.empty()) {
    for (const auto& [_, kv] : merged_environment) {
      const auto& key = kv.first;
      const auto& value = kv.second;
      const std::string entry = key + "=" + value;
      env_block.insert(env_block.end(), entry.begin(), entry.end());
      env_block.push_back('\0');
    }
    // Windows requires a double-NUL terminated environment block.
    env_block.push_back('\0');
    environment = env_block.data();
  }

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
      environment,
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

bool JumperSdkPlatformPlugin::IsRealProcessAlive() const {
  if (!has_real_process_ || process_info_.hProcess == nullptr) {
    return false;
  }
  const DWORD wait_result = WaitForSingleObject(process_info_.hProcess, 0);
  return wait_result == WAIT_TIMEOUT;
}

bool JumperSdkPlatformPlugin::WaitForCoreReady(
    const LaunchOptions& options,
    std::string* error) const {
  const int core_api_port = ResolveCoreApiPort(options.arguments);
  // Gate "success" on process stability to avoid reporting connected
  // immediately after a short-lived startup.
  int stable_checks = 0;
  const int required_stable_checks = 8;  // ~800ms
  const int max_checks = 50;             // ~5s
  bool process_stable = false;
  bool core_api_ready = false;
  for (int i = 0; i < max_checks; i++) {
    if (!IsRealProcessAlive()) {
      DWORD exit_code = 0;
      if (process_info_.hProcess != nullptr &&
          GetExitCodeProcess(process_info_.hProcess, &exit_code) != 0 &&
          exit_code != STILL_ACTIVE) {
        if (error != nullptr) {
          *error = "Core process exited during startup, exit code " +
                   std::to_string(exit_code);
        }
      } else if (error != nullptr) {
        *error = "Core process exited during startup";
      }
      return false;
    }
    stable_checks += 1;
    if (stable_checks >= required_stable_checks) {
      process_stable = true;
      if (core_api_port > 0 && IsCoreApiReachable(core_api_port)) {
        core_api_ready = true;
        return true;
      }
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }

  if (error != nullptr) {
    if (!process_stable) {
      *error = "Core process startup readiness timeout";
    } else if (core_api_port <= 0) {
      *error = "Core API port missing from launch config";
    } else if (!core_api_ready) {
      *error = "Core API not reachable after startup on 127.0.0.1:" +
               std::to_string(core_api_port);
    } else {
      *error = "Core readiness check failed";
    }
  }
  return false;
}

int JumperSdkPlatformPlugin::ResolveCoreApiPort(
    const std::vector<std::string>& arguments) const {
  std::string config_path;
  for (size_t i = 0; i < arguments.size(); ++i) {
    if (arguments[i] == "-c" && i + 1 < arguments.size()) {
      config_path = arguments[i + 1];
      break;
    }
  }
  if (config_path.empty()) {
    return 0;
  }
  std::ifstream file(config_path);
  if (!file.is_open()) {
    return 0;
  }
  const std::string content((std::istreambuf_iterator<char>(file)),
                            std::istreambuf_iterator<char>());
  file.close();
  const std::regex controller_regex(
      "\"external_controller\"\\s*:\\s*\"([^\"]+)\"");
  std::smatch controller_match;
  if (!std::regex_search(content, controller_match, controller_regex)) {
    return 0;
  }
  const std::string controller = controller_match[1].str();
  const size_t colon = controller.rfind(':');
  if (colon == std::string::npos || colon + 1 >= controller.size()) {
    return 0;
  }
  try {
    return std::stoi(controller.substr(colon + 1));
  } catch (...) {
    return 0;
  }
}

bool JumperSdkPlatformPlugin::IsCoreApiReachable(int port) const {
  if (port <= 0 || port > 65535) {
    return false;
  }
  static const bool wsa_ready = []() {
    WSADATA wsa_data{};
    return WSAStartup(MAKEWORD(2, 2), &wsa_data) == 0;
  }();
  if (!wsa_ready) {
    return false;
  }
  SOCKET socket_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (socket_fd == INVALID_SOCKET) {
    return false;
  }
  sockaddr_in address{};
  address.sin_family = AF_INET;
  address.sin_port = htons(static_cast<u_short>(port));
  address.sin_addr.s_addr = inet_addr("127.0.0.1");
  u_long non_blocking = 1;
  ioctlsocket(socket_fd, FIONBIO, &non_blocking);
  const int connect_result =
      connect(socket_fd, reinterpret_cast<const sockaddr*>(&address), sizeof(address));
  bool ok = false;
  if (connect_result == 0) {
    ok = true;
  } else {
    const int last_error = WSAGetLastError();
    if (last_error == WSAEWOULDBLOCK || last_error == WSAEINPROGRESS) {
      fd_set write_set;
      FD_ZERO(&write_set);
      FD_SET(socket_fd, &write_set);
      timeval timeout{};
      timeout.tv_sec = 1;
      timeout.tv_usec = 0;
      const int ready = select(0, nullptr, &write_set, nullptr, &timeout);
      if (ready > 0 && FD_ISSET(socket_fd, &write_set)) {
        int socket_error = 0;
        int opt_len = sizeof(socket_error);
        if (getsockopt(
                socket_fd,
                SOL_SOCKET,
                SO_ERROR,
                reinterpret_cast<char*>(&socket_error),
                &opt_len) == 0 &&
            socket_error == 0) {
          ok = true;
        }
      }
    }
  }
  closesocket(socket_fd);
  return ok;
}

bool JumperSdkPlatformPlugin::IsTunInboundEnabledInConfig(
    const std::string& config_path) const {
  std::ifstream file(config_path);
  if (!file.is_open()) {
    return false;
  }
  const std::string content((std::istreambuf_iterator<char>(file)),
                            std::istreambuf_iterator<char>());
  file.close();

  const auto tun_inbound = ParseTunInboundFromConfig(content);
  if (tun_inbound.empty()) {
    return false;
  }
  const auto enable_it = tun_inbound.find("enable");
  if (enable_it == tun_inbound.end()) {
    // Missing "enable" means enabled by default in sing-box semantics.
    return true;
  }
  std::string enable_value = Trim(enable_it->second);
  std::transform(
      enable_value.begin(),
      enable_value.end(),
      enable_value.begin(),
      [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return enable_value != "false";
}

std::unordered_map<std::string, std::string>
JumperSdkPlatformPlugin::ParseFlatJsonObject(const std::string& json_object) const {
  std::unordered_map<std::string, std::string> result;
  const std::regex pair_regex(
      R"("([^"]+)"\s*:\s*("(?:[^"\\]|\\.)*"|true|false|null|-?\d+(?:\.\d+)?))");
  for (std::sregex_iterator it(json_object.begin(), json_object.end(), pair_regex), end;
       it != end; ++it) {
    result[it->str(1)] = it->str(2);
  }
  return result;
}

std::unordered_map<std::string, std::string>
JumperSdkPlatformPlugin::ParseTunInboundFromConfig(const std::string& content) const {
  // Parse only top-level objects from inbounds array and locate type=tun.
  const size_t inbounds_key = content.find("\"inbounds\"");
  if (inbounds_key == std::string::npos) {
    return {};
  }
  size_t array_start = content.find('[', inbounds_key);
  if (array_start == std::string::npos) {
    return {};
  }
  size_t index = array_start + 1;
  int depth = 0;
  bool in_string = false;
  bool escape = false;
  size_t object_start = std::string::npos;
  while (index < content.size()) {
    const char c = content[index];
    if (escape) {
      escape = false;
      index++;
      continue;
    }
    if (c == '\\' && in_string) {
      escape = true;
      index++;
      continue;
    }
    if (c == '"') {
      in_string = !in_string;
      index++;
      continue;
    }
    if (in_string) {
      index++;
      continue;
    }
    if (c == '[') {
      depth++;
      index++;
      continue;
    }
    if (c == ']') {
      if (depth == 0) {
        break;
      }
      depth--;
      index++;
      continue;
    }
    if (c == '{') {
      if (depth == 0) {
        object_start = index;
      }
      depth++;
      index++;
      continue;
    }
    if (c == '}') {
      depth--;
      if (depth == 0 && object_start != std::string::npos) {
        const std::string object = content.substr(object_start, index - object_start + 1);
        const auto object_map = ParseFlatJsonObject(object);
        const auto type_it = object_map.find("type");
        if (type_it != object_map.end()) {
          std::string type_value = Trim(type_it->second);
          if (!type_value.empty() && type_value.front() == '"' &&
              type_value.back() == '"' && type_value.size() >= 2) {
            type_value = type_value.substr(1, type_value.size() - 2);
          }
          std::transform(
              type_value.begin(),
              type_value.end(),
              type_value.begin(),
              [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
          if (type_value == "tun") {
            return object_map;
          }
        }
      }
      index++;
      continue;
    }
    index++;
  }
  return {};
}

std::string JumperSdkPlatformPlugin::Trim(const std::string& value) const {
  const auto is_space = [](unsigned char c) { return std::isspace(c) != 0; };
  auto begin = std::find_if_not(value.begin(), value.end(), is_space);
  if (begin == value.end()) {
    return "";
  }
  auto end = std::find_if_not(value.rbegin(), value.rend(), is_space).base();
  return std::string(begin, end);
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
      if (network_mode_ == "tunnel" &&
          !IsTunnelEnabledInLaunchConfig(launch_options.arguments)) {
        result->Error(
            "TUNNEL_CONFIG_NOT_ENABLED",
            "Network mode is tunnel, but launch config does not enable tun inbound",
            flutter::EncodableValue());
        return;
      }

      std::string error;
      if (!StartRealCore(launch_options, &error)) {
        is_running_ = false;
        runtime_mode_ = "simulator";
        pid_ = 0;
        result->Error("START_CORE_FAILED", "Failed to start core process", error);
        return;
      }
      if (!WaitForCoreReady(launch_options, &error)) {
        StopRealCore();
        is_running_ = false;
        runtime_mode_ = "simulator";
        pid_ = 0;
        result->Error("START_CORE_FAILED", "Core started but failed readiness gate", error);
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
      if (network_mode_ == "tunnel" &&
          !IsTunnelEnabledInLaunchConfig(launch_options.arguments)) {
        result->Error(
            "TUNNEL_CONFIG_NOT_ENABLED",
            "Network mode is tunnel, but launch config does not enable tun inbound",
            flutter::EncodableValue());
        return;
      }

      std::string error;
      if (!StartRealCore(launch_options, &error)) {
        is_running_ = false;
        runtime_mode_ = "simulator";
        pid_ = 0;
        result->Error("RESTART_CORE_FAILED", "Failed to restart core process", error);
        return;
      }
      if (!WaitForCoreReady(launch_options, &error)) {
        StopRealCore();
        is_running_ = false;
        runtime_mode_ = "simulator";
        pid_ = 0;
        result->Error("RESTART_CORE_FAILED", "Core restarted but failed readiness gate", error);
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
    if (has_real_process_ && !IsRealProcessAlive()) {
      if (process_info_.hProcess != nullptr) {
        CloseHandle(process_info_.hProcess);
        process_info_.hProcess = nullptr;
      }
      if (process_info_.hThread != nullptr) {
        CloseHandle(process_info_.hThread);
        process_info_.hThread = nullptr;
      }
      has_real_process_ = false;
      is_running_ = false;
      pid_ = 0;
    }
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
    RuntimeRequest request;
    std::string parse_error;
    if (!ParseRuntimeRequest(method_call, true, &request, &parse_error)) {
      result->Error("SETUP_RUNTIME_FAILED", "Failed to setup runtime in container", parse_error);
      return;
    }
    const std::string runtime_root = RuntimeContainerRoot();
    const std::string source_binary =
        request.base_path + "\\engine\\runtime-assets\\" + request.platform_arch +
        "\\sing-box-" + request.version + "-" + request.platform_arch + "\\sing-box.exe";
    const std::string source_config =
        request.base_path + "\\engine\\runtime-assets\\" + request.platform_arch +
        "\\minimal-config.json";
    const std::string target_binary = runtime_root + "\\sing-box.exe";
    const std::string target_config = runtime_root + "\\config.json";
    const std::string target_version = runtime_root + "\\VERSION";

    std::string io_error;
    if (!EnsureDirectory(runtime_root, &io_error) ||
        !CopyFileReplace(source_binary, target_binary, &io_error) ||
        !CopyFileReplace(source_config, target_config, &io_error) ||
        !WriteTextFile(target_version, request.version + "\n", &io_error)) {
      result->Error("SETUP_RUNTIME_FAILED", "Failed to setup runtime in container", io_error);
      return;
    }

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("installed")] = flutter::EncodableValue(true);
    payload[flutter::EncodableValue("binaryPath")] = flutter::EncodableValue(target_binary);
    payload[flutter::EncodableValue("configPath")] = flutter::EncodableValue(target_config);
    payload[flutter::EncodableValue("runtimeRoot")] = flutter::EncodableValue(runtime_root);
    result->Success(flutter::EncodableValue(payload));
  } else if (method_call.method_name().compare("inspectRuntime") == 0) {
    RuntimeRequest request;
    std::string parse_error;
    if (!ParseRuntimeRequest(method_call, false, &request, &parse_error)) {
      result->Error("INSPECT_RUNTIME_FAILED", "Failed to inspect runtime", parse_error);
      return;
    }
    const std::string runtime_root = RuntimeContainerRoot();
    const std::string binary_path = runtime_root + "\\sing-box.exe";
    const std::string config_path = runtime_root + "\\config.json";
    const std::string version_path = runtime_root + "\\VERSION";
    std::string runtime_version;
    {
      std::ifstream input(version_path);
      if (input.is_open()) {
        std::getline(input, runtime_version);
      }
    }
    const bool binary_exists = FileExists(binary_path);
    const bool config_exists = FileExists(config_path);
    const bool version_matches = runtime_version == request.version;

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("ready")] =
        flutter::EncodableValue(binary_exists && config_exists && version_matches);
    payload[flutter::EncodableValue("binaryPath")] = flutter::EncodableValue(binary_path);
    payload[flutter::EncodableValue("configPath")] = flutter::EncodableValue(config_path);
    payload[flutter::EncodableValue("binaryExists")] = flutter::EncodableValue(binary_exists);
    payload[flutter::EncodableValue("configExists")] = flutter::EncodableValue(config_exists);
    payload[flutter::EncodableValue("runtimeVersion")] = flutter::EncodableValue(runtime_version);
    payload[flutter::EncodableValue("expectedVersion")] = flutter::EncodableValue(request.version);
    payload[flutter::EncodableValue("versionMatches")] = flutter::EncodableValue(version_matches);
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
