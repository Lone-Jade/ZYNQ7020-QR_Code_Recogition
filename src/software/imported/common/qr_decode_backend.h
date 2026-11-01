#ifndef QR_DECODE_BACKEND_H
#define QR_DECODE_BACKEND_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int version;
    int ecc_level;
    int mask;
    int data_type;
    uint32_t eci;
    int mirrored;
    int backend_error;
} qr_decode_info_t;

/*
 * Decode a row-major, one-byte-per-module matrix. Non-zero means dark.
 * Returns 0 on success, a positive quirc error on standards decode failure,
 * and a negative value for invalid arguments or a short output buffer.
 */
int qr_decode_modules(const uint8_t *modules, int size,
                      char *payload, size_t payload_capacity,
                      qr_decode_info_t *info);

const char *qr_decode_error_string(int error);

#ifdef __cplusplus
}
#endif

#endif
