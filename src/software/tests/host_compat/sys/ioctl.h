#ifndef QR_HOST_IOCTL_H
#define QR_HOST_IOCTL_H
#include <linux/ioctl.h>
int ioctl(int fd,unsigned long request,...);
#endif
