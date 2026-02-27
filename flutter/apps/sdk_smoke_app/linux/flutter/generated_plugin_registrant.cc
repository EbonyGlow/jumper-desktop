//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <jumper_sdk_platform/jumper_sdk_platform_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) jumper_sdk_platform_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "JumperSdkPlatformPlugin");
  jumper_sdk_platform_plugin_register_with_registrar(jumper_sdk_platform_registrar);
}
