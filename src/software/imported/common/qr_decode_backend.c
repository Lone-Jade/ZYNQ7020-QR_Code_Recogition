#include "qr_decode_backend.h"

#include "quirc.h"

#include <string.h>

/* Static storage avoids placing quirc's maximum payload and bitmap structures
 * on the small bare-metal stack. V1 is single-threaded and decodes one symbol
 * at a time, so a non-reentrant backend is intentional. */
static struct quirc_code g_code;
static struct quirc_data g_data;

int qr_decode_modules(const uint8_t *modules, int size,
                      char *payload, size_t payload_capacity,
                      qr_decode_info_t *info)
{
    quirc_decode_error_t error;
    int count;
    int index;
    int mirrored = 0;

    if ((modules == NULL) || (payload == NULL) || (payload_capacity == 0U))
        return -1;
    if ((size < 21) || (size > QUIRC_MAX_GRID_SIZE) || (((size - 17) & 3) != 0))
        return -2;

    memset(&g_code, 0, sizeof(g_code));
    memset(&g_data, 0, sizeof(g_data));
    if (info != NULL)
        memset(info, 0, sizeof(*info));
    payload[0] = '\0';
    g_code.size = size;
    count = size * size;
    for (index = 0; index < count; ++index) {
        if (modules[index] != 0U)
            g_code.cell_bitmap[index >> 3] |= (uint8_t)(1U << (index & 7));
    }

    error = quirc_decode(&g_code, &g_data);
    if (error == QUIRC_ERROR_DATA_ECC) {
        quirc_flip(&g_code);
        error = quirc_decode(&g_code, &g_data);
        mirrored = 1;
    }
    if (info != NULL) {
        info->version = g_data.version;
        info->ecc_level = g_data.ecc_level;
        info->mask = g_data.mask;
        info->data_type = g_data.data_type;
        info->eci = g_data.eci;
        info->mirrored = mirrored;
        info->backend_error = (int)error;
    }
    if (error != QUIRC_SUCCESS)
        return (int)error;
    if ((size_t)g_data.payload_len + 1U > payload_capacity)
        return -3;
    memcpy(payload, g_data.payload, (size_t)g_data.payload_len);
    payload[g_data.payload_len] = '\0';
    return 0;
}

const char *qr_decode_error_string(int error)
{
    if (error == -1)
        return "invalid argument";
    if (error == -2)
        return "invalid module matrix size";
    if (error == -3)
        return "payload buffer too small";
    switch ((quirc_decode_error_t)error) {
    case QUIRC_SUCCESS:
        return "success";
    case QUIRC_ERROR_INVALID_GRID_SIZE:
        return "invalid grid size";
    case QUIRC_ERROR_INVALID_VERSION:
        return "invalid version";
    case QUIRC_ERROR_FORMAT_ECC:
        return "format data ECC failure";
    case QUIRC_ERROR_DATA_ECC:
        return "payload data ECC failure";
    case QUIRC_ERROR_UNKNOWN_DATA_TYPE:
        return "unknown data type";
    case QUIRC_ERROR_DATA_OVERFLOW:
        return "data overflow";
    case QUIRC_ERROR_DATA_UNDERFLOW:
        return "data underflow";
    }
    return "unknown backend error";
}
