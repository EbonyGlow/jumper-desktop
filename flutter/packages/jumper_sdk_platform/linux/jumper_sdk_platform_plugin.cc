#include "include/jumper_sdk_platform/jumper_sdk_platform_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <signal.h>
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
      [&](FlValue* args, gchar** binary_path, gchar*** launch_args, gchar** working_dir) {
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
                                GError** error) {
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
    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "installed", fl_value_new_bool(FALSE));
    fl_value_set_string_take(payload, "ready", fl_value_new_bool(FALSE));
    fl_value_set_string_take(payload, "platform", fl_value_new_string("linux"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
  } else if (strcmp(method, "inspectRuntime") == 0) {
    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "ready", fl_value_new_bool(FALSE));
    fl_value_set_string_take(payload, "binaryExists", fl_value_new_bool(FALSE));
    fl_value_set_string_take(payload, "configExists", fl_value_new_bool(FALSE));
    fl_value_set_string_take(payload, "platform", fl_value_new_string("linux"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
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
