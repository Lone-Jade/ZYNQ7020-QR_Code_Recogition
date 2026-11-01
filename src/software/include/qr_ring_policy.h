#ifndef QR_RING_POLICY_H
#define QR_RING_POLICY_H
enum qr_buffer_state { QR_BUF_FREE, QR_BUF_QUEUED, QR_BUF_DONE, QR_BUF_USER };
static inline unsigned qr_ring_free(const unsigned *state,unsigned count){
 unsigned i;for(i=0;i<count;i++)if(state[i]==QR_BUF_FREE)return i;return count;
}
static inline unsigned qr_ring_oldest(const unsigned *state,const unsigned long long *seq,unsigned count){
 unsigned i,b=count;for(i=0;i<count;i++)if(state[i]==QR_BUF_DONE&&(b==count||seq[i]<seq[b]))b=i;return b;
}
static inline int qr_ring_release_valid(unsigned state,unsigned long long actual,unsigned long long requested){
 return state==QR_BUF_USER&&actual==requested;
}
#endif
