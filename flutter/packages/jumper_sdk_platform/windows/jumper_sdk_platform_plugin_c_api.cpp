#include "include/jumper_sdk_platform/jumper_sdk_platform_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "jumper_sdk_platform_plugin.h"

void JumperSdkPlatformPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  jumper_sdk_platform::JumperSdkPlatformPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
