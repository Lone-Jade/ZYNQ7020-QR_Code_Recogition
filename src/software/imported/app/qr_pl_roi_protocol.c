#include "qr_pl_roi_protocol.h"

int qr_pl_guards_valid(const qr_pl_guard_t *h, const qr_pl_guard_t *f,
                       uint32_t width, uint32_t height, uint32_t format,
                       uint32_t epoch, uint32_t config_seq)
{
    if (!h || !f || width < 64U || width > 65535U || height > 65535U)
        return 0;
    return h->magic == QR_PL_HEADER_MAGIC && f->magic == QR_PL_FOOTER_MAGIC &&
        h->version == QR_PL_ABI_VERSION && f->version == h->version &&
        h->epoch == epoch && f->epoch == h->epoch &&
        h->config_seq == config_seq && f->config_seq == h->config_seq &&
        h->frame_seq_inverse == ~h->frame_seq && f->frame_seq == h->frame_seq &&
        f->frame_seq_inverse == h->frame_seq_inverse &&
        h->format == format && f->format == h->format &&
        h->dimensions == (width | (height << 16)) &&
        f->dimensions == h->dimensions && h->threshold <= 255U &&
        f->reserved[0] == h->reserved[0] && f->reserved[1] == h->reserved[1] &&
        f->reserved[2] == h->reserved[2] && f->reserved[3] == h->reserved[3] &&
        f->threshold == h->threshold && f->threshold_source == h->threshold_source &&
        h->pixels == 0U && h->flags == 0U && f->pixels == width * height &&
        f->flags == QR_PL_COMPLETE;
}

int qr_pl_bank_matches(const qr_pl_bank_t *b, const qr_pl_guard_t *h)
{
    return b && h && !(b->generation & 1U) && b->generation != 0U &&
        b->epoch == h->epoch && b->frame_seq == h->frame_seq &&
        b->config_seq == h->config_seq && b->threshold == h->threshold &&
        b->threshold_source == h->threshold_source && b->roi_count <= QR_PL_ROI_LIMIT &&
        b->reserved[0] == h->reserved[0] && b->reserved[1] == h->reserved[1] &&
        b->reserved[2] == h->reserved[2] && b->reserved[3] == h->reserved[3] &&
        (b->flags & QR_PL_COMPLETE) && !(b->flags & (QR_PL_AXIS_ERROR | QR_PL_TIMEOUT));
}

int qr_pl_roi_valid(const qr_pl_roi_t *r, uint32_t width, uint32_t height)
{
    unsigned i;
    if (!r || qr_pl_x(r->min_xy) >= qr_pl_x(r->max_xy) ||
        qr_pl_y(r->min_xy) >= qr_pl_y(r->max_xy) ||
        qr_pl_x(r->max_xy) > width || qr_pl_y(r->max_xy) > height ||
        (r->module_angle & 65535U) == 0U)
        return 0;
    for (i = 0; i < 3; ++i)
        if (qr_pl_x(r->finder_xy[i]) >= width || qr_pl_y(r->finder_xy[i]) >= height)
            return 0;
    return 1;
}
