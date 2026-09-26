#include <node_api.h>

#include <cmath>
#include <cstddef>
#include <cstdint>

namespace {
constexpr std::size_t kMaxComponents = 100000 * 3;
constexpr double kMaxDeltaSeconds = 0.05;
constexpr double kMaxComponent = 1000000.0;
constexpr double kAttraction = 0.35;
constexpr double kDamping = 0.8;

struct FloatView {
  float* data = nullptr;
  std::size_t length = 0;
};

bool Check(napi_env env, napi_status status) {
  if (status == napi_ok) return true;
  if (status != napi_pending_exception) {
    napi_throw_error(env, "ERR_PARTICLE_NAPI", "Node-API operation failed");
  }
  return false;
}

bool ReadFloatView(napi_env env, napi_value value, FloatView* view) {
  bool is_typed_array = false;
  if (!Check(env, napi_is_typedarray(env, value, &is_typed_array))) return false;
  if (!is_typed_array) {
    napi_throw_type_error(env, "ERR_PARTICLE_TYPE", "positions and velocities must be Float32Array values");
    return false;
  }

  napi_typedarray_type type;
  napi_value buffer;
  std::size_t byte_offset = 0;
  void* data = nullptr;
  if (!Check(env, napi_get_typedarray_info(env, value, &type, &view->length,
                                         &data, &buffer, &byte_offset))) return false;
  if (type != napi_float32_array) {
    napi_throw_type_error(env, "ERR_PARTICLE_TYPE", "positions and velocities must be Float32Array values");
    return false;
  }

  bool is_array_buffer = false;
  if (!Check(env, napi_is_arraybuffer(env, buffer, &is_array_buffer))) return false;
  // SharedArrayBuffer must be rejected: concurrent writes would invalidate the
  // validation pass, and ordinary float accesses would have a C++ data race.
  if (!is_array_buffer) {
    napi_throw_type_error(env, "ERR_PARTICLE_SHARED", "SharedArrayBuffer storage is not supported");
    return false;
  }
  bool detached = false;
  if (!Check(env, napi_is_detached_arraybuffer(env, buffer, &detached))) return false;
  if (detached || data == nullptr || view->length == 0 ||
      view->length > kMaxComponents || view->length % 3 != 0) {
    napi_throw_range_error(env, "ERR_PARTICLE_LENGTH", "arrays must contain 1 to 100000 xyz particles in attached storage");
    return false;
  }
  view->data = static_cast<float*>(data);
  return true;
}

bool InBounds(double value) {
  return std::isfinite(value) && std::abs(value) <= kMaxComponent;
}

bool Overlap(const FloatView& left, const FloatView& right) {
  const auto left_start = reinterpret_cast<std::uintptr_t>(left.data);
  const auto right_start = reinterpret_cast<std::uintptr_t>(right.data);
  // Difference comparisons avoid pointer arithmetic outside an allocation and
  // integer overflow from adding a length to an address.
  return left_start <= right_start
      ? right_start - left_start < left.length * sizeof(float)
      : left_start - right_start < right.length * sizeof(float);
}

napi_value Update(napi_env env, napi_callback_info info) {
  std::size_t argc = 4;
  napi_value args[4];
  if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr))) return nullptr;
  if (argc != 3) {
    napi_throw_type_error(env, "ERR_PARTICLE_ARGS", "update requires exactly positions, velocities, and deltaSeconds");
    return nullptr;
  }

  FloatView positions;
  FloatView velocities;
  if (!ReadFloatView(env, args[0], &positions) ||
      !ReadFloatView(env, args[1], &velocities)) return nullptr;
  if (positions.length != velocities.length || Overlap(positions, velocities)) {
    napi_throw_range_error(env, "ERR_PARTICLE_LAYOUT", "arrays must have equal lengths and non-overlapping storage");
    return nullptr;
  }

  napi_valuetype delta_type;
  if (!Check(env, napi_typeof(env, args[2], &delta_type))) return nullptr;
  if (delta_type != napi_number) {
    napi_throw_type_error(env, "ERR_PARTICLE_DELTA", "deltaSeconds must be a number");
    return nullptr;
  }
  double delta = 0.0;
  if (!Check(env, napi_get_value_double(env, args[2], &delta))) return nullptr;
  if (!std::isfinite(delta) || delta < 0.0 || delta > kMaxDeltaSeconds) {
    napi_throw_range_error(env, "ERR_PARTICLE_DELTA", "deltaSeconds must be finite and between 0 and 0.05");
    return nullptr;
  }

  const double attenuation = std::exp(-kDamping * delta);
  // Validate the complete batch and its proposed output before writing either
  // array. This function invokes no JS callbacks and accepts no shared storage.
  for (std::size_t i = 0; i < positions.length; ++i) {
    const double position = positions.data[i];
    const double velocity = velocities.data[i];
    const double next_velocity = (velocity - kAttraction * position * delta) * attenuation;
    const double next_position = position + next_velocity * delta;
    if (!InBounds(position) || !InBounds(velocity) ||
        !InBounds(next_position) || !InBounds(next_velocity)) {
      napi_throw_range_error(env, "ERR_PARTICLE_BOUNDS", "all input and output components must be finite and within +/-1000000");
      return nullptr;
    }
  }

  // Get the return value before mutation, so no fallible Node-API operation is
  // performed after committing the batch.
  napi_value result;
  if (!Check(env, napi_get_undefined(env, &result))) return nullptr;
  if (delta == 0.0) return result;
  for (std::size_t i = 0; i < positions.length; ++i) {
    const double position = positions.data[i];
    const double next_velocity =
        (velocities.data[i] - kAttraction * position * delta) * attenuation;
    velocities.data[i] = static_cast<float>(next_velocity);
    positions.data[i] = static_cast<float>(position + next_velocity * delta);
  }
  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_value update;
  if (!Check(env, napi_create_function(env, "update", NAPI_AUTO_LENGTH, Update,
                                       nullptr, &update)) ||
      !Check(env, napi_set_named_property(env, exports, "update", update))) return nullptr;
  return exports;
}
}  // namespace

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
