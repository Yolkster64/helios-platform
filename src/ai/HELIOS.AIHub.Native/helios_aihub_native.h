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

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* HELIOS_AIHUB_NATIVE_H */
