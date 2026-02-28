#include "include/jumper_sdk_platform/jumper_sdk_platform_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/utsname.h>

#include <cstring>

#include "jumper_sdk_platform_plugin_private.h"

#define JUMPER_SDK_PLATFORM_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), jumper_sdk_platform_plugin_get_type(), \
                              JumperSdkPlatformPlugin))

struct _JumperSdkPlatformPlugin {
  GObject parent_instance;
  gboolean is_running;
  gint64 pid;
  gchar* profile_id;
  gchar* runtime_mode;
  gchar* network_mode;
  GPid real_pid;
  gboolean has_real_process;
  gchar* last_binary_path;
  gchar** last_arguments;
  gchar* last_working_directory;
};

G_DEFINE_TYPE(JumperSdkPlatformPlugin, jumper_sdk_platform_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void jumper_sdk_platform_plugin_handle_method_call(
    JumperSdkPlatformPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  auto stop_real_process = [&]() {
    if (!self->has_real_process) {
      return;
    }
    if (self->real_pid > 0) {
      kill(self->real_pid, SIGTERM);
      g_spawn_close_pid(self->real_pid);
    }
    self->real_pid = 0;
    self->has_real_process = FALSE;
  };

  auto parse_launch_options =
      [&](FlValue* args, gchar** binary_path, gchar*** launch_args, gchar** working_dir) -> gboolean {
        *binary_path = nullptr;
        *launch_args = nullptr;
        *working_dir = nullptr;
        if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
          return FALSE;
        }
        FlValue* launch = fl_value_lookup_string(args, "launchOptions");
        if (launch == nullptr || fl_value_get_type(launch) != FL_VALUE_TYPE_MAP) {
          return FALSE;
        }
        FlValue* binary = fl_value_lookup_string(launch, "binaryPath");
        if (binary == nullptr || fl_value_get_type(binary) != FL_VALUE_TYPE_STRING) {
          return FALSE;
        }
        const gchar* binary_text = fl_value_get_string(binary);
        if (binary_text == nullptr || strlen(binary_text) == 0) {
          return FALSE;
        }
        *binary_path = g_strdup(binary_text);

        FlValue* arg_values = fl_value_lookup_string(launch, "arguments");
        GPtrArray* ptr_array = g_ptr_array_new_with_free_func(g_free);
        g_ptr_array_add(ptr_array, g_strdup(binary_text));
        if (arg_values != nullptr && fl_value_get_type(arg_values) == FL_VALUE_TYPE_LIST) {
          const size_t count = fl_value_get_length(arg_values);
          for (size_t i = 0; i < count; ++i) {
            FlValue* entry = fl_value_get_list_value(arg_values, i);
            if (entry != nullptr && fl_value_get_type(entry) == FL_VALUE_TYPE_STRING) {
              g_ptr_array_add(ptr_array, g_strdup(fl_value_get_string(entry)));
            }
          }
        }
        g_ptr_array_add(ptr_array, nullptr);
        *launch_args = reinterpret_cast<gchar**>(g_ptr_array_free(ptr_array, FALSE));

        FlValue* wd = fl_value_lookup_string(launch, "workingDirectory");
        if (wd != nullptr && fl_value_get_type(wd) == FL_VALUE_TYPE_STRING) {
          const gchar* wd_text = fl_value_get_string(wd);
          if (wd_text != nullptr && strlen(wd_text) > 0) {
            *working_dir = g_strdup(wd_text);
          }
        }
        return TRUE;
      };

  auto start_real_process = [&](gchar* binary_path, gchar** launch_args, gchar* working_dir,
                                GError** error) -> gboolean {
    stop_real_process();
    GPid pid = 0;
    const gboolean started = g_spawn_async(
        working_dir,
        launch_args,
        nullptr,
        static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
        nullptr,
        nullptr,
        &pid,
        error);
    if (!started) {
      return FALSE;
    }
    self->real_pid = pid;
    self->has_real_process = TRUE;
    self->pid = pid;
    g_clear_pointer(&self->last_binary_path, g_free);
    self->last_binary_path = g_strdup(binary_path);
    g_strfreev(self->last_arguments);
    self->last_arguments = g_strdupv(launch_args);
    g_clear_pointer(&self->last_working_directory, g_free);
    self->last_working_directory = working_dir == nullptr ? nullptr : g_strdup(working_dir);
    return TRUE;
  };

  auto parse_runtime_request =
      [&](FlMethodCall* call, gboolean require_base_path, gchar** version, gchar** platform_arch,
          gchar** base_path, GError** error) -> gboolean {
        *version = nullptr;
        *platform_arch = nullptr;
        *base_path = nullptr;
        FlValue* args = fl_method_call_get_args(call);
        if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
          g_set_error(error, g_quark_from_static_string("jumper.runtime"), 1, "Missing arguments");
          return FALSE;
        }
        FlValue* version_value = fl_value_lookup_string(args, "version");
        FlValue* arch_value = fl_value_lookup_string(args, "platformArch");
        FlValue* base_value = fl_value_lookup_string(args, "basePath");
        if (version_value == nullptr || fl_value_get_type(version_value) != FL_VALUE_TYPE_STRING ||
            strlen(fl_value_get_string(version_value)) == 0) {
          g_set_error(error, g_quark_from_static_string("jumper.runtime"), 2, "Missing version");
          return FALSE;
        }
        if (arch_value == nullptr || fl_value_get_type(arch_value) != FL_VALUE_TYPE_STRING ||
            strlen(fl_value_get_string(arch_value)) == 0) {
          g_set_error(
              error, g_quark_from_static_string("jumper.runtime"), 3, "Missing platformArch");
          return FALSE;
        }
        const gchar* base_text =
            (base_value != nullptr && fl_value_get_type(base_value) == FL_VALUE_TYPE_STRING)
                ? fl_value_get_string(base_value)
                : "";
        if (require_base_path && (base_text == nullptr || strlen(base_text) == 0)) {
          g_set_error(error, g_quark_from_static_string("jumper.runtime"), 4, "Missing basePath");
          return FALSE;
        }
        *version = g_strdup(fl_value_get_string(version_value));
        *platform_arch = g_strdup(fl_value_get_string(arch_value));
        *base_path = g_strdup(base_text == nullptr ? "" : base_text);
        return TRUE;
      };

  auto runtime_container_root = [&]() -> gchar* {
    const gchar* user_data = g_get_user_data_dir();
    if (user_data != nullptr && strlen(user_data) > 0) {
      return g_build_filename(user_data, "jumper-runtime", nullptr);
    }
    return g_build_filename(g_get_home_dir(), ".local", "share", "jumper-runtime", nullptr);
  };

  auto copy_file_replace = [&](const gchar* source, const gchar* destination, GError** error) -> gboolean {
    gchar* bytes = nullptr;
    gsize length = 0;
    if (!g_file_get_contents(source, &bytes, &length, error)) {
      return FALSE;
    }
    gboolean ok = g_file_set_contents(destination, bytes, static_cast<gssize>(length), error);
    g_free(bytes);
    return ok;
  };

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else if (strcmp(method, "startCore") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    gchar* binary_path = nullptr;
    gchar** launch_args = nullptr;
    gchar* working_dir = nullptr;
    const gboolean has_launch =
        parse_launch_options(args, &binary_path, &launch_args, &working_dir);
    g_clear_pointer(&self->profile_id, g_free);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* profile_id = fl_value_lookup_string(args, "profileId");
      if (profile_id != nullptr && fl_value_get_type(profile_id) == FL_VALUE_TYPE_STRING) {
        self->profile_id = g_strdup(fl_value_get_string(profile_id));
      }
      FlValue* network_mode = fl_value_lookup_string(args, "networkMode");
      if (network_mode != nullptr &&
          fl_value_get_type(network_mode) == FL_VALUE_TYPE_STRING &&
          strlen(fl_value_get_string(network_mode)) > 0) {
        g_free(self->network_mode);
        self->network_mode = g_strdup(fl_value_get_string(network_mode));
      }
    }
    if (has_launch) {
      GError* spawn_error = nullptr;
      if (!start_real_process(binary_path, launch_args, working_dir, &spawn_error)) {
        self->is_running = FALSE;
        self->pid = 0;
        g_free(self->runtime_mode);
        self->runtime_mode = g_strdup("simulator");
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "START_CORE_FAILED",
            "Failed to start core process",
            fl_value_new_string(spawn_error == nullptr ? "unknown" : spawn_error->message)));
        if (spawn_error != nullptr) {
          g_error_free(spawn_error);
        }
        g_free(binary_path);
        g_strfreev(launch_args);
        g_free(working_dir);
      } else {
        self->is_running = TRUE;
        g_free(self->runtime_mode);
        self->runtime_mode = g_strdup("real");
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        g_free(binary_path);
        g_strfreev(launch_args);
        g_free(working_dir);
      }
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    self->is_running = TRUE;
    g_free(self->runtime_mode);
    self->runtime_mode = g_strdup("simulator");
    self->pid = g_get_real_time();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "stopCore") == 0) {
    stop_real_process();
    self->is_running = FALSE;
    self->pid = 0;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "restartCore") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    gchar* binary_path = nullptr;
    gchar** launch_args = nullptr;
    gchar* working_dir = nullptr;
    gboolean has_launch = parse_launch_options(args, &binary_path, &launch_args, &working_dir);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* network_mode = fl_value_lookup_string(args, "networkMode");
      if (network_mode != nullptr &&
          fl_value_get_type(network_mode) == FL_VALUE_TYPE_STRING &&
          strlen(fl_value_get_string(network_mode)) > 0) {
        g_free(self->network_mode);
        self->network_mode = g_strdup(fl_value_get_string(network_mode));
      }
    }
    if (!has_launch && self->last_arguments != nullptr && self->last_binary_path != nullptr) {
      has_launch = TRUE;
      binary_path = g_strdup(self->last_binary_path);
      launch_args = g_strdupv(self->last_arguments);
      working_dir =
          self->last_working_directory == nullptr ? nullptr : g_strdup(self->last_working_directory);
    }
    if (has_launch) {
      GError* spawn_error = nullptr;
      if (!start_real_process(binary_path, launch_args, working_dir, &spawn_error)) {
        self->is_running = FALSE;
        self->pid = 0;
        g_free(self->runtime_mode);
        self->runtime_mode = g_strdup("simulator");
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "RESTART_CORE_FAILED",
            "Failed to restart core process",
            fl_value_new_string(spawn_error == nullptr ? "unknown" : spawn_error->message)));
        if (spawn_error != nullptr) {
          g_error_free(spawn_error);
        }
      } else {
        self->is_running = TRUE;
        g_free(self->runtime_mode);
        self->runtime_mode = g_strdup("real");
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      }
      g_free(binary_path);
      g_strfreev(launch_args);
      g_free(working_dir);
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    self->is_running = TRUE;
    g_free(self->runtime_mode);
    self->runtime_mode = g_strdup("simulator");
    self->pid = g_get_real_time();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "resetTunnel") == 0) {
    if (self->is_running) {
      self->pid = g_get_real_time();
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "getCoreState") == 0) {
    g_autoptr(FlValue) state = fl_value_new_map();
    fl_value_set_string_take(state, "status",
                             self->is_running ? fl_value_new_string("running")
                                              : fl_value_new_string("stopped"));
    fl_value_set_string_take(
        state, "runtimeMode",
        fl_value_new_string(self->runtime_mode != nullptr ? self->runtime_mode : "simulator"));
    fl_value_set_string_take(
        state, "networkMode",
        fl_value_new_string(self->network_mode != nullptr ? self->network_mode : "tunnel"));
    if (self->pid > 0) {
      fl_value_set_string_take(state, "pid", fl_value_new_int(self->pid));
    }
    if (self->profile_id != nullptr) {
      fl_value_set_string_take(state, "profileId", fl_value_new_string(self->profile_id));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(state));
  } else if (strcmp(method, "setupRuntime") == 0) {
    gchar* version = nullptr;
    gchar* platform_arch = nullptr;
    gchar* base_path = nullptr;
    GError* runtime_error = nullptr;
    if (!parse_runtime_request(method_call, TRUE, &version, &platform_arch, &base_path, &runtime_error)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "SETUP_RUNTIME_FAILED",
          "Failed to setup runtime in container",
          fl_value_new_string(runtime_error == nullptr ? "unknown" : runtime_error->message)));
      if (runtime_error != nullptr) {
        g_error_free(runtime_error);
      }
      g_free(version);
      g_free(platform_arch);
      g_free(base_path);
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    g_autofree gchar* runtime_root = runtime_container_root();
    if (g_mkdir_with_parents(runtime_root, 0755) != 0) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "SETUP_RUNTIME_FAILED",
          "Failed to setup runtime in container",
          fl_value_new_string("Unable to create runtime root")));
      g_free(version);
      g_free(platform_arch);
      g_free(base_path);
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    g_autofree gchar* source_binary = g_strdup_printf(
        "%s/engine/runtime-assets/%s/sing-box-%s-%s/sing-box",
        base_path, platform_arch, version, platform_arch);
    g_autofree gchar* source_config = g_strdup_printf(
        "%s/engine/runtime-assets/%s/minimal-config.json",
        base_path, platform_arch);
    g_autofree gchar* target_binary = g_build_filename(runtime_root, "sing-box", nullptr);
    g_autofree gchar* target_config = g_build_filename(runtime_root, "config.json", nullptr);
    g_autofree gchar* target_version = g_build_filename(runtime_root, "VERSION", nullptr);

    if (!copy_file_replace(source_binary, target_binary, &runtime_error) ||
        !copy_file_replace(source_config, target_config, &runtime_error) ||
        !g_file_set_contents(target_version, version, -1, &runtime_error)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "SETUP_RUNTIME_FAILED",
          "Failed to setup runtime in container",
          fl_value_new_string(runtime_error == nullptr ? "unknown" : runtime_error->message)));
      if (runtime_error != nullptr) {
        g_error_free(runtime_error);
      }
      g_free(version);
      g_free(platform_arch);
      g_free(base_path);
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    chmod(target_binary, 0755);

    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "installed", fl_value_new_bool(TRUE));
    fl_value_set_string_take(payload, "binaryPath", fl_value_new_string(target_binary));
    fl_value_set_string_take(payload, "configPath", fl_value_new_string(target_config));
    fl_value_set_string_take(payload, "runtimeRoot", fl_value_new_string(runtime_root));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
    g_free(version);
    g_free(platform_arch);
    g_free(base_path);
  } else if (strcmp(method, "inspectRuntime") == 0) {
    gchar* version = nullptr;
    gchar* platform_arch = nullptr;
    gchar* base_path = nullptr;
    GError* runtime_error = nullptr;
    if (!parse_runtime_request(method_call, FALSE, &version, &platform_arch, &base_path, &runtime_error)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INSPECT_RUNTIME_FAILED",
          "Failed to inspect runtime",
          fl_value_new_string(runtime_error == nullptr ? "unknown" : runtime_error->message)));
      if (runtime_error != nullptr) {
        g_error_free(runtime_error);
      }
      g_free(version);
      g_free(platform_arch);
      g_free(base_path);
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    g_autofree gchar* runtime_root = runtime_container_root();
    g_autofree gchar* binary_path = g_build_filename(runtime_root, "sing-box", nullptr);
    g_autofree gchar* config_path = g_build_filename(runtime_root, "config.json", nullptr);
    g_autofree gchar* version_path = g_build_filename(runtime_root, "VERSION", nullptr);
    gboolean binary_exists = g_file_test(binary_path, G_FILE_TEST_EXISTS);
    gboolean config_exists = g_file_test(config_path, G_FILE_TEST_EXISTS);
    gchar* runtime_version = nullptr;
    gsize runtime_version_len = 0;
    if (!g_file_get_contents(version_path, &runtime_version, &runtime_version_len, nullptr)) {
      runtime_version = g_strdup("");
    }
    gchar* runtime_version_trimmed = g_strstrip(runtime_version);
    gboolean version_matches = g_strcmp0(runtime_version_trimmed, version) == 0;

    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(
        payload, "ready", fl_value_new_bool(binary_exists && config_exists && version_matches));
    fl_value_set_string_take(payload, "binaryPath", fl_value_new_string(binary_path));
    fl_value_set_string_take(payload, "configPath", fl_value_new_string(config_path));
    fl_value_set_string_take(payload, "binaryExists", fl_value_new_bool(binary_exists));
    fl_value_set_string_take(payload, "configExists", fl_value_new_bool(config_exists));
    fl_value_set_string_take(
        payload, "runtimeVersion", fl_value_new_string(runtime_version_trimmed == nullptr ? "" : runtime_version_trimmed));
    fl_value_set_string_take(payload, "expectedVersion", fl_value_new_string(version));
    fl_value_set_string_take(payload, "versionMatches", fl_value_new_bool(version_matches));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
    g_free(runtime_version);
    g_free(version);
    g_free(platform_arch);
    g_free(base_path);
  } else if (strcmp(method, "enableSystemProxy") == 0 ||
             strcmp(method, "disableSystemProxy") == 0 ||
             strcmp(method, "requestNotificationPermission") == 0 ||
             strcmp(method, "showNotification") == 0 ||
             strcmp(method, "showTray") == 0 ||
             strcmp(method, "updateTray") == 0 ||
             strcmp(method, "hideTray") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "PLATFORM_CAPABILITY_NOT_IMPLEMENTED",
        "Capability is not implemented on Linux plugin yet.",
        fl_value_new_string(method)));
  } else if (strcmp(method, "getSystemProxyStatus") == 0) {
    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "enabled", fl_value_new_bool(FALSE));
    fl_value_set_string_take(payload, "platform", fl_value_new_string("linux"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
  } else if (strcmp(method, "getNotificationPermissionStatus") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
  } else if (strcmp(method, "getTrayStatus") == 0) {
    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "visible", fl_value_new_bool(FALSE));
    fl_value_set_string_take(payload, "title", fl_value_new_string(""));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
  } else if (strcmp(method, "getPlatformCapabilities") == 0) {
    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "tunnelSupported", fl_value_new_bool(TRUE));
    fl_value_set_string_take(payload, "systemProxySupported", fl_value_new_bool(FALSE));
    fl_value_set_string_take(payload, "notifySupported", fl_value_new_bool(FALSE));
    fl_value_set_string_take(payload, "traySupported", fl_value_new_bool(FALSE));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void jumper_sdk_platform_plugin_dispose(GObject* object) {
  JumperSdkPlatformPlugin* self = JUMPER_SDK_PLATFORM_PLUGIN(object);
  if (self->has_real_process && self->real_pid > 0) {
    kill(self->real_pid, SIGTERM);
    g_spawn_close_pid(self->real_pid);
  }
  g_clear_pointer(&self->profile_id, g_free);
  g_clear_pointer(&self->runtime_mode, g_free);
  g_clear_pointer(&self->network_mode, g_free);
  g_clear_pointer(&self->last_binary_path, g_free);
  g_strfreev(self->last_arguments);
  g_clear_pointer(&self->last_working_directory, g_free);
  G_OBJECT_CLASS(jumper_sdk_platform_plugin_parent_class)->dispose(object);
}

static void jumper_sdk_platform_plugin_class_init(JumperSdkPlatformPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = jumper_sdk_platform_plugin_dispose;
}

static void jumper_sdk_platform_plugin_init(JumperSdkPlatformPlugin* self) {
  self->is_running = FALSE;
  self->pid = 0;
  self->profile_id = nullptr;
  self->runtime_mode = g_strdup("simulator");
  self->network_mode = g_strdup("tunnel");
  self->real_pid = 0;
  self->has_real_process = FALSE;
  self->last_binary_path = nullptr;
  self->last_arguments = nullptr;
  self->last_working_directory = nullptr;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  JumperSdkPlatformPlugin* plugin = JUMPER_SDK_PLATFORM_PLUGIN(user_data);
  jumper_sdk_platform_plugin_handle_method_call(plugin, method_call);
}

void jumper_sdk_platform_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  JumperSdkPlatformPlugin* plugin = JUMPER_SDK_PLATFORM_PLUGIN(
      g_object_new(jumper_sdk_platform_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "jumper_sdk_platform",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
