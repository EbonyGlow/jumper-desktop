#ifndef FLUTTER_PLUGIN_JUMPER_SDK_PLATFORM_PLUGIN_H_
#define FLUTTER_PLUGIN_JUMPER_SDK_PLATFORM_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <string>
#include <map>
#include <unordered_map>
#include <vector>
#include <windows.h>

namespace jumper_sdk_platform {

class JumperSdkPlatformPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  JumperSdkPlatformPlugin();

  virtual ~JumperSdkPlatformPlugin();

  // Disallow copy and assign.
  JumperSdkPlatformPlugin(const JumperSdkPlatformPlugin&) = delete;
  JumperSdkPlatformPlugin& operator=(const JumperSdkPlatformPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  struct LaunchOptions {
    std::string binary_path;
    std::vector<std::string> arguments;
    std::string working_directory;
    std::map<std::string, std::string> environment;
  };
  struct RuntimeRequest {
    std::string version;
    std::string platform_arch;
    std::string base_path;
  };

  bool StartRealCore(const LaunchOptions& options, std::string* error);
  void StopRealCore();
  bool IsTunnelEnabledInLaunchConfig(const std::vector<std::string>& arguments) const;
  bool IsRealProcessAlive() const;
  bool WaitForCoreReady(const LaunchOptions& options, std::string* error) const;
  int ResolveCoreApiPort(const std::vector<std::string>& arguments) const;
  bool IsCoreApiReachable(int port) const;
  bool IsTunInboundEnabledInConfig(const std::string& config_path) const;
  std::unordered_map<std::string, std::string> ParseFlatJsonObject(
      const std::string& json_object) const;
  std::unordered_map<std::string, std::string> ParseTunInboundFromConfig(
      const std::string& content) const;
  std::string Trim(const std::string& value) const;
  bool ParseLaunchOptions(const flutter::EncodableMap& args, LaunchOptions* options);
  bool ParseRuntimeRequest(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      bool require_base_path,
      RuntimeRequest* request,
      std::string* error);
  std::string RuntimeContainerRoot() const;
  bool EnsureDirectory(const std::string& path, std::string* error) const;
  bool CopyFileReplace(const std::string& source, const std::string& destination, std::string* error) const;
  bool WriteTextFile(const std::string& path, const std::string& value, std::string* error) const;
  bool FileExists(const std::string& path) const;

  bool is_running_ = false;
  int64_t pid_ = 0;
  std::string profile_id_;
  std::string runtime_mode_ = "simulator";
  std::string network_mode_ = "tunnel";
  PROCESS_INFORMATION process_info_{};
  bool has_real_process_ = false;
  bool has_last_launch_options_ = false;
  LaunchOptions last_launch_options_{};
};

}  // namespace jumper_sdk_platform

#endif  // FLUTTER_PLUGIN_JUMPER_SDK_PLATFORM_PLUGIN_H_
