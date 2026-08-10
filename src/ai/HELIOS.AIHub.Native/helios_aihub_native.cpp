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

constexpr int32_t kAbiVersion = 1;

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

    // Count characters, not bytes: a multi-byte character is usually one token, so byte
    // length alone overestimates CJK and accented text badly.
    size_t characters = 0;
    for (size_t i = 0; i < byte_length; ++i) {
        if (!is_utf8_continuation(static_cast<unsigned char>(utf8_text[i]))) {
            ++characters;
        }
    }

    const double estimate = static_cast<double>(characters) / kBytesPerToken;
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

    const double allowed_characters = static_cast<double>(max_tokens) * kBytesPerToken;
    size_t characters = 0;
    size_t index = 0;
    while (index < byte_length) {
        if (!is_utf8_continuation(static_cast<unsigned char>(utf8_text[index]))) {
            if (static_cast<double>(characters) >= allowed_characters) {
                break;
            }
            ++characters;
        }
        ++index;
    }

    *out_byte_length = back_off_to_boundary(utf8_text, index);
    return HELIOS_OK;
}

}  // extern "C"
