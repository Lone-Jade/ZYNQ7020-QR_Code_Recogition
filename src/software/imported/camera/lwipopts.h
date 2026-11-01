#ifndef OV5640_ETH_LWIPOPTS_H
#define OV5640_ETH_LWIPOPTS_H

#define NO_SYS                    1
#define LWIP_SOCKET               0
#define LWIP_NETCONN              0
#define LWIP_RAW                  1
#define MEM_SIZE                  (32 * 1024)
#define MEMP_NUM_PBUF             256
#define PBUF_POOL_SIZE            256
#define PBUF_POOL_BUFSIZE         1536
#define LWIP_UDP                  1
#define LWIP_ICMP                 1
#define IP_FORWARD                0
#define TCPIP_THREAD_STACKSIZE    2048
#define DEFAULT_THREAD_STACKSIZE  2048
#define CHECKSUM_GEN_UDP          1
#define CHECKSUM_CHECK_UDP        1

#endif
