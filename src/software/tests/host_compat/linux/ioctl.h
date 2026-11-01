#ifndef QR_HOST_IOCTL_CONSTANTS_H
#define QR_HOST_IOCTL_CONSTANTS_H
#define _IOC(d,t,n,s) (((unsigned long)(d)<<30)|((unsigned long)(s)<<16)|((unsigned long)(t)<<8)|(n))
#define _IO(t,n) _IOC(0,t,n,0)
#define _IOR(t,n,s) _IOC(2,t,n,sizeof(s))
#define _IOW(t,n,s) _IOC(1,t,n,sizeof(s))
#define _IOWR(t,n,s) _IOC(3,t,n,sizeof(s))
#endif
