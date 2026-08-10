// HELIOS AIHub native helpers. See helios_aihub_native.h for the memory contract.
//
// Style notes for anyone extending this: every entry point validates its arguments and
// returns a status rather than throwing, because exceptions must not cross the C ABI.
// Loops are written so the compiler can vectorize them (unit stride, no aliasing between
// input and output, no early exits) rather than reaching for intrinsics — auto-vectorized
// code stays portable across MSVC, clang-cl, and gcc, and the generated code is
// equivalent here. Reach for intrinsics only when a profile says this is the bottleneck.

#include "helios_aihub_native.h"

#include <cmath>
#include <cstring>

namespace {

constexpr int32_t kAbiVersion = 2;

// Empirical average bytes-per-token for English-ish UTF-8 across common BPE tokenizers.
// Text that is mostly code or CJK diverges, which is why the header calls this an
// estimate and forbids using it for billing.
constexpr double kBytesPerToken = 3.85;

inline bool is_utf8_continuation(unsigned char byte) {
    return (byte & 0xC0u) == 0x80u;
}

// Walk backwards to the start of the character containing `index`, so a truncation never
// splits a multi-byte sequence. Bounded by 4 steps: no UTF-8 sequence is longer.
size_t back_off_to_boundary(const char* text, size_t index) {
    size_t steps = 0;
    while (index > 0 && steps < 4 &&
           is_utf8_continuation(static_cast<unsigned char>(text[index]))) {
        --index;
        ++steps;
    }
    return index;
}

// ---- MLP routing learner ----

// Seed 0 would freeze xorshift at zero forever; remap it to a non-zero constant
// (the 64-bit golden-ratio increment) so every seed value is usable.
constexpr uint64_t kSeedFallback = 0x9E3779B97F4A7C15ULL;

// xorshift64*: tiny, deterministic, and statistically good enough for weight init.
// Not for cryptography — and deliberately not std::mt19937, whose stream is not
// guaranteed bit-identical across standard library implementations.
uint64_t next_random(uint64_t& state) {
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    return state * 0x2545F4914F6CDD1DULL;
}

// Uniform in [-limit, limit]. Top 53 bits => exactly representable fraction in [0,1).
double uniform_in(uint64_t& state, double limit) {
    const double fraction = static_cast<double>(next_random(state) >> 11) * 0x1.0p-53;
    return (2.0 * fraction - 1.0) * limit;
}

// Branch on sign so exp() never overflows for large |x|.
double stable_sigmoid(double x) {
    if (x >= 0.0) {
        return 1.0 / (1.0 + std::exp(-x));
    }
    const double e = std::exp(x);
    return e / (1.0 + e);
}

// Offsets into the flat weight buffer. Layout (documented in the header):
// W1[hidden][dim], b1[hidden], W2[hidden], b2.
struct MlpLayout {
    size_t dim;
    size_t hidden;

    size_t w1(size_t unit) const { return unit * dim; }
    size_t b1() const { return hidden * dim; }
    size_t w2() const { return hidden * dim + hidden; }
    size_t b2() const { return hidden * (dim + 2); }
    size_t count() const { return hidden * (dim + 2) + 1; }
};

helios_status validate_mlp_shape(size_t feature_dim, size_t hidden_units) {
    if (feature_dim == 0 || hidden_units == 0 || hidden_units > HELIOS_MLP_MAX_HIDDEN) {
        return HELIOS_ERR_BAD_LENGTH;
    }
    return HELIOS_OK;
}

// Forward pass: tanh hidden activations into caller scratch, sigmoid output.
// Double accumulation for the same reason as cosine similarity above.
double mlp_forward(const float* weights, const MlpLayout& layout,
                   const float* features, double* hidden_act) {
    for (size_t h = 0; h < layout.hidden; ++h) {
        const float* row = weights + layout.w1(h);
        double sum = static_cast<double>(weights[layout.b1() + h]);
        for (size_t d = 0; d < layout.dim; ++d) {
            sum += static_cast<double>(row[d]) * static_cast<double>(features[d]);
        }
        hidden_act[h] = std::tanh(sum);
    }

    double output = static_cast<double>(weights[layout.b2()]);
    const float* w2 = weights + layout.w2();
    for (size_t h = 0; h < layout.hidden; ++h) {
        output += static_cast<double>(w2[h]) * hidden_act[h];
    }
    return stable_sigmoid(output);
}

}  // namespace

extern "C" {

int32_t helios_abi_version(void) {
    return kAbiVersion;
}

helios_status helios_cosine_similarity(
    const float* a, const float* b, size_t length, float* out_similarity) {
    if (a == nullptr || b == nullptr || out_similarity == nullptr) {
        return HELIOS_ERR_NULL_ARG;
    }
    if (length == 0) {
        return HELIOS_ERR_BAD_LENGTH;
    }

    // Accumulate in double: float accumulation over thousands of dimensions loses
    // meaningful precision, and this value drives dedup decisions.
    double dot = 0.0;
    double norm_a = 0.0;
    double norm_b = 0.0;
    for (size_t i = 0; i < length; ++i) {
        const double x = static_cast<double>(a[i]);
        const double y = static_cast<double>(b[i]);
        dot += x * y;
        norm_a += x * x;
        norm_b += y * y;
    }

    const double denom = std::sqrt(norm_a) * std::sqrt(norm_b);
    *out_similarity = (denom < 1e-12) ? 0.0f : static_cast<float>(dot / denom);
    return HELIOS_OK;
}

helios_status helios_similarity_matrix(
    const float* vectors, size_t count, size_t dim, float* out_matrix) {
    if (vectors == nullptr || out_matrix == nullptr) {
        return HELIOS_ERR_NULL_ARG;
    }
    if (count == 0 || dim == 0) {
        return HELIOS_ERR_BAD_LENGTH;
    }

    for (size_t i = 0; i < count; ++i) {
        out_matrix[i * count + i] = 1.0f;
        // Only the upper triangle is computed; the matrix is symmetric, so this halves
        // the work on what is an O(count^2 * dim) operation.
        for (size_t j = i + 1; j < count; ++j) {
            float similarity = 0.0f;
            const helios_status status = helios_cosine_similarity(
                vectors + i * dim, vectors + j * dim, dim, &similarity);
            if (status != HELIOS_OK) {
                return status;
            }
            out_matrix[i * count + j] = similarity;
            out_matrix[j * count + i] = similarity;
        }
    }
    return HELIOS_OK;
}

helios_status helios_estimate_tokens(
    const char* utf8_text, size_t byte_length, int32_t* out_tokens) {
    if (out_tokens == nullptr) {
        return HELIOS_ERR_NULL_ARG;
    }
    if (utf8_text == nullptr && byte_length != 0) {
        return HELIOS_ERR_NULL_ARG;
    }
    if (byte_length == 0) {
        *out_tokens = 0;
        return HELIOS_OK;
    }

    // Two regimes, not one: ASCII text averages kBytesPerToken characters per
    // token, while a multi-byte character (CJK, accented) is roughly one token
    // by itself. Dividing a mixed character count by kBytesPerToken would
    // undercount CJK-heavy prompts ~4x and route them into windows they can't
    // fit.
    size_t ascii_chars = 0;
    size_t multibyte_chars = 0;
    for (size_t i = 0; i < byte_length; ++i) {
        const auto byte = static_cast<unsigned char>(utf8_text[i]);
        if (is_utf8_continuation(byte)) {
            continue;
        }
        if (byte < 0x80) {
            ++ascii_chars;
        } else {
            ++multibyte_chars;
        }
    }

    const double estimate =
        static_cast<double>(ascii_chars) / kBytesPerToken + static_cast<double>(multibyte_chars);
    *out_tokens = static_cast<int32_t>(estimate < 1.0 ? 1.0 : estimate);
    return HELIOS_OK;
}

helios_status helios_fit_prefix_bytes(
    const char* utf8_text, size_t byte_length, int32_t max_tokens, size_t* out_byte_length) {
    if (out_byte_length == nullptr) {
        return HELIOS_ERR_NULL_ARG;
    }
    if (utf8_text == nullptr && byte_length != 0) {
        return HELIOS_ERR_NULL_ARG;
    }
    if (max_tokens <= 0) {
        *out_byte_length = 0;
        return HELIOS_OK;
    }

    int32_t total = 0;
    const helios_status status = helios_estimate_tokens(utf8_text, byte_length, &total);
    if (status != HELIOS_OK) {
        return status;
    }
    if (total <= max_tokens) {
        *out_byte_length = byte_length;
        return HELIOS_OK;
    }

    // Walk with the same per-character weights as helios_estimate_tokens so a
    // fitted prefix re-estimates within max_tokens.
    const double budget = static_cast<double>(max_tokens);
    double used = 0.0;
    size_t index = 0;
    while (index < byte_length) {
        const auto byte = static_cast<unsigned char>(utf8_text[index]);
        if (!is_utf8_continuation(byte)) {
            const double weight = byte < 0x80 ? 1.0 / kBytesPerToken : 1.0;
            if (used + weight > budget) {
                break;
            }
            used += weight;
        }
        ++index;
    }

    *out_byte_length = back_off_to_boundary(utf8_text, index);
    return HELIOS_OK;
}

helios_status helios_mlp_weight_count(
    size_t feature_dim, size_t hidden_units, size_t* out_weight_count) {
    if (out_weight_count == nullptr) {
        return HELIOS_ERR_NULL_ARG;
    }
    const helios_status shape = validate_mlp_shape(feature_dim, hidden_units);
    if (shape != HELIOS_OK) {
        return shape;
    }

    const MlpLayout layout{feature_dim, hidden_units};
    *out_weight_count = layout.count();
    return HELIOS_OK;
}

helios_status helios_mlp_init(
    float* weights, size_t weight_count,
    size_t feature_dim, size_t hidden_units, uint64_t seed) {
    if (weights == nullptr) {
        return HELIOS_ERR_NULL_ARG;
    }
    const helios_status shape = validate_mlp_shape(feature_dim, hidden_units);
    if (shape != HELIOS_OK) {
        return shape;
    }
    const MlpLayout layout{feature_dim, hidden_units};
    if (weight_count != layout.count()) {
        return HELIOS_ERR_DIMENSION_MISMATCH;
    }

    uint64_t state = (seed == 0) ? kSeedFallback : seed;

    // Xavier-uniform: limit sqrt(6 / (fan_in + fan_out)) per layer keeps early
    // activations in tanh's linear region so gradients neither vanish nor explode.
    const double w1_limit =
        std::sqrt(6.0 / static_cast<double>(feature_dim + hidden_units));
    const double w2_limit = std::sqrt(6.0 / static_cast<double>(hidden_units + 1));

    for (size_t h = 0; h < hidden_units; ++h) {
        float* row = weights + layout.w1(h);
        for (size_t d = 0; d < feature_dim; ++d) {
            row[d] = static_cast<float>(uniform_in(state, w1_limit));
        }
    }
    for (size_t h = 0; h < hidden_units; ++h) {
        weights[layout.b1() + h] = 0.0f;
    }
    for (size_t h = 0; h < hidden_units; ++h) {
        weights[layout.w2() + h] = static_cast<float>(uniform_in(state, w2_limit));
    }
    weights[layout.b2()] = 0.0f;
    return HELIOS_OK;
}

helios_status helios_mlp_train(
    float* weights, size_t weight_count,
    size_t feature_dim, size_t hidden_units,
    const float* features, const float* targets, size_t sample_count,
    int32_t epochs, float learning_rate, float l2_regularization, float* out_mean_loss) {
    if (weights == nullptr || features == nullptr || targets == nullptr) {
        return HELIOS_ERR_NULL_ARG;
    }
    const helios_status shape = validate_mlp_shape(feature_dim, hidden_units);
    if (shape != HELIOS_OK) {
        return shape;
    }
    if (sample_count == 0 || epochs <= 0 || !(learning_rate > 0.0f) ||
        l2_regularization < 0.0f) {
        return HELIOS_ERR_BAD_LENGTH;
    }
    const MlpLayout layout{feature_dim, hidden_units};
    if (weight_count != layout.count()) {
        return HELIOS_ERR_DIMENSION_MISMATCH;
    }

    const double lr = static_cast<double>(learning_rate);
    const double l2 = static_cast<double>(l2_regularization);
    double hidden_act[HELIOS_MLP_MAX_HIDDEN];
    double epoch_loss = 0.0;

    for (int32_t epoch = 0; epoch < epochs; ++epoch) {
        epoch_loss = 0.0;
        for (size_t s = 0; s < sample_count; ++s) {
            const float* x = features + s * feature_dim;
            double target = static_cast<double>(targets[s]);
            target = (target < 0.0) ? 0.0 : (target > 1.0 ? 1.0 : target);

            const double p = mlp_forward(weights, layout, x, hidden_act);

            // Clamp before log: p can round to exactly 0 or 1 in float-adjacent math.
            const double p_safe =
                (p < 1e-12) ? 1e-12 : (p > 1.0 - 1e-12 ? 1.0 - 1e-12 : p);
            epoch_loss -= target * std::log(p_safe) +
                          (1.0 - target) * std::log(1.0 - p_safe);

            // Sigmoid + cross-entropy: output delta collapses to (p - t).
            const double delta_out = p - target;

            for (size_t h = 0; h < hidden_units; ++h) {
                // Read W2[h] before updating it: delta_h must use the value that
                // produced this forward pass, or backprop is subtly wrong.
                const double w2h = static_cast<double>(weights[layout.w2() + h]);
                const double a_h = hidden_act[h];
                const double grad_w2 = delta_out * a_h + l2 * w2h;
                const double delta_h = delta_out * w2h * (1.0 - a_h * a_h);

                weights[layout.w2() + h] = static_cast<float>(w2h - lr * grad_w2);

                float* row = weights + layout.w1(h);
                for (size_t d = 0; d < feature_dim; ++d) {
                    const double w = static_cast<double>(row[d]);
                    row[d] = static_cast<float>(
                        w - lr * (delta_h * static_cast<double>(x[d]) + l2 * w));
                }
                // No L2 on biases: shrinking them only shifts the decision surface.
                weights[layout.b1() + h] = static_cast<float>(
                    static_cast<double>(weights[layout.b1() + h]) - lr * delta_h);
            }
            weights[layout.b2()] = static_cast<float>(
                static_cast<double>(weights[layout.b2()]) - lr * delta_out);
        }
    }

    if (out_mean_loss != nullptr) {
        *out_mean_loss =
            static_cast<float>(epoch_loss / static_cast<double>(sample_count));
    }
    return HELIOS_OK;
}

helios_status helios_mlp_predict(
    const float* weights, size_t weight_count,
    size_t feature_dim, size_t hidden_units,
    const float* features, size_t sample_count, float* out_scores) {
    if (weights == nullptr || features == nullptr || out_scores == nullptr) {
        return HELIOS_ERR_NULL_ARG;
    }
    const helios_status shape = validate_mlp_shape(feature_dim, hidden_units);
    if (shape != HELIOS_OK) {
        return shape;
    }
    if (sample_count == 0) {
        return HELIOS_ERR_BAD_LENGTH;
    }
    const MlpLayout layout{feature_dim, hidden_units};
    if (weight_count != layout.count()) {
        return HELIOS_ERR_DIMENSION_MISMATCH;
    }

    double hidden_act[HELIOS_MLP_MAX_HIDDEN];
    for (size_t s = 0; s < sample_count; ++s) {
        out_scores[s] = static_cast<float>(
            mlp_forward(weights, layout, features + s * feature_dim, hidden_act));
    }
    return HELIOS_OK;
}

}  // extern "C"
