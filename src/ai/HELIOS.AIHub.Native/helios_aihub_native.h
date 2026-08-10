/*
 * HELIOS AIHub native helpers — flat C ABI.
 *
 * Hub-and-spoke: this library is a *spoke*. It exposes a C ABI that only the C#
 * orchestrator calls (via LibraryImport). It never calls back into managed code, never
 * performs I/O, and never talks to another spoke. Everything here is a pure computation
 * over caller-owned memory.
 *
 * Why native at all: token-window accounting and response similarity run over every
 * request in a fan-out, and both are tight numeric loops over large buffers where the
 * managed allocator and bounds checks show up in profiles. Everything else belongs in C#.
 *
 * Memory contract: the caller owns every buffer. No function allocates, frees, retains a
 * pointer past return, or throws. That is what makes the boundary safe to cross.
 */

#ifndef HELIOS_AIHUB_NATIVE_H
#define HELIOS_AIHUB_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#  define HELIOS_API __declspec(dllexport)
#else
#  define HELIOS_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Status codes. Negative values are errors; the boundary never throws. */
typedef enum helios_status {
    HELIOS_OK = 0,
    HELIOS_ERR_NULL_ARG = -1,
    HELIOS_ERR_BAD_LENGTH = -2,
    HELIOS_ERR_DIMENSION_MISMATCH = -3
} helios_status;

/* ABI version. The C# side checks this on first call so a stale native binary fails
 * loudly at startup instead of corrupting results later. */
HELIOS_API int32_t helios_abi_version(void);

/*
 * Cosine similarity between two equal-length embedding vectors.
 * Used to detect near-duplicate replies when fanning one prompt across providers.
 * Writes the result to *out_similarity in [-1, 1]. Zero-magnitude vectors yield 0.
 */
HELIOS_API helios_status helios_cosine_similarity(
    const float* a, const float* b, size_t length, float* out_similarity);

/*
 * Pairwise cosine similarity across `count` vectors of `dim` each, stored contiguously
 * (row-major). Writes a count*count row-major matrix into out_matrix, which the caller
 * must size to count*count floats.
 */
HELIOS_API helios_status helios_similarity_matrix(
    const float* vectors, size_t count, size_t dim, float* out_matrix);

/*
 * Approximate token count for UTF-8 text, without a tokenizer.
 * Deliberately an estimate: it exists to decide "will this fit / roughly what will this
 * cost" before a call, where being within a few percent instantly beats being exact
 * slowly. Never use it for billing — providers report real usage in their responses.
 */
HELIOS_API helios_status helios_estimate_tokens(
    const char* utf8_text, size_t byte_length, int32_t* out_tokens);

/*
 * Largest prefix of `utf8_text` that fits in max_tokens by the same estimate, returned as
 * a byte length that always lands on a UTF-8 character boundary (never splits a
 * multi-byte sequence, which would produce invalid text downstream).
 */
HELIOS_API helios_status helios_fit_prefix_bytes(
    const char* utf8_text, size_t byte_length, int32_t max_tokens, size_t* out_byte_length);

/*
 * Online routing learner: a single-hidden-layer MLP (tanh hidden, sigmoid output)
 * trained sample-by-sample with SGD on cross-entropy loss.
 *
 * Why a hidden layer instead of the linear scoring the F# domain already does: provider
 * outcomes interact non-linearly — "fast but flaky under load" vs "slow but reliable on
 * long prompts" is exactly the kind of feature interaction a linear score cannot
 * represent (the classic XOR case, which the test suite uses as its proof of learning).
 * The managed side owns feature engineering and persistence of the weight buffer; this
 * code owns only the arithmetic.
 *
 * Weight buffer layout (caller-owned, sized via helios_mlp_weight_count):
 *   W1[hidden][dim] , b1[hidden] , W2[hidden] , b2   — contiguous floats in that order.
 *
 * Determinism: same binary + same seed + same sample order => bit-identical weights.
 * Samples are consumed in caller order (no internal shuffle) so replaying a learning
 * store yields a reproducible model. Targets are clamped to [0,1]; soft targets are fine
 * (cross-entropy generalizes), so a blended success/quality reward works as a label.
 */

/* Hidden-layer cap: keeps scratch on the stack, honoring the no-allocation contract. */
#define HELIOS_MLP_MAX_HIDDEN 256

HELIOS_API helios_status helios_mlp_weight_count(
    size_t feature_dim, size_t hidden_units, size_t* out_weight_count);

/* Xavier-uniform init from a deterministic PRNG; biases start at zero. */
HELIOS_API helios_status helios_mlp_init(
    float* weights, size_t weight_count,
    size_t feature_dim, size_t hidden_units, uint64_t seed);

/*
 * Run `epochs` passes of online SGD over `sample_count` rows of `features`
 * (row-major, feature_dim wide) against `targets` in [0,1]. Updates `weights` in
 * place; writes the mean loss of the final epoch to *out_mean_loss when non-null,
 * so callers can log convergence without recomputing it.
 */
HELIOS_API helios_status helios_mlp_train(
    float* weights, size_t weight_count,
    size_t feature_dim, size_t hidden_units,
    const float* features, const float* targets, size_t sample_count,
    int32_t epochs, float learning_rate, float l2_regularization, float* out_mean_loss);

/* Sigmoid scores in (0,1), one per input row — higher means "expect success". */
HELIOS_API helios_status helios_mlp_predict(
    const float* weights, size_t weight_count,
    size_t feature_dim, size_t hidden_units,
    const float* features, size_t sample_count, float* out_scores);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* HELIOS_AIHUB_NATIVE_H */
