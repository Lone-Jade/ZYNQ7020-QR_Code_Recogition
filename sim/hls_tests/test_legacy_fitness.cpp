#include "qr_fitness.h"
#include <vector>
#include <cstdio>
#include <cmath>
#include <cstring>
#include <random>
#include <cassert>
extern "C" {
#define new c04_new_value
#include "../../src/software/imported/quirc/identify.c"
#undef new
}

static void cell(std::vector<uint32_t>& f,int x,int y,int w){f.push_back(unsigned(x)|(unsigned(y)<<8)|(unsigned(uint8_t(w))<<16));}
static void ring(std::vector<uint32_t>&f,int x,int y,int r,int w){for(int i=0;i<2*r;i++){
    cell(f,x-r+i,y-r,w);cell(f,x-r,y+r-i,w);cell(f,x+r,y-r+i,w);cell(f,x+r-i,y+r,w);}}
static void cap(std::vector<uint32_t>&f,int x,int y){x+=3;y+=3;cell(f,x,y,1);ring(f,x,y,1,1);ring(f,x,y,2,-1);ring(f,x,y,3,1);}
static void apat(std::vector<uint32_t>&f,int x,int y){cell(f,x,y,1);ring(f,x,y,1,-1);ring(f,x,y,2,1);}
static std::vector<uint32_t> features(int size){std::vector<uint32_t> f;
    for(int i=0;i<size-14;i++){int w=(i&1)?1:-1;cell(f,i+7,6,w);cell(f,6,i+7,w);}
    cap(f,0,0);cap(f,size-7,0);cap(f,0,size-7);
    const auto &info=quirc_version_db[(size-17)/4];int n=0;while(n<QUIRC_MAX_ALIGNMENT&&info.apat[n])n++;
    for(int i=1;i+1<n;i++){apat(f,6,info.apat[i]);apat(f,info.apat[i],6);}
    for(int i=1;i<n;i++)for(int j=1;j<n;j++)apat(f,info.apat[i],info.apat[j]);return f;
}

int main(int argc,char**){std::mt19937 random(7021);unsigned jobs=0;
    for(int version=1;version<=40;version++){
        if(argc>1&&version!=1&&version!=20&&version!=40)continue;
        int size=version*4+17,width=argc>1?256:253+version%5,height=argc>1?240:237+version%4,stride=(width+31)/32;
        std::vector<uint8_t> pixels(width*height);std::vector<uint32_t> memory(stride*height);
        for(int y=0;y<height;y++)for(int x=0;x<width;x++){unsigned i=y*width+x;pixels[i]=(random()&1)?1:0;if(pixels[i])memory[y*stride+(x>>5)]|=1u<<(x&31);}
        auto f=features(size);assert(f.size()<=QR_FITNESS_CELLS);memory.insert(memory.end(),f.begin(),f.end());
        struct quirc q={};q.w=width;q.h=height;q.pixels=pixels.data();q.num_grids=1;q.grids[0].grid_size=size;
        int32_t score;uint32_t status,job;
        qr_fitness(memory.data(),0,width,height,stride,f.size(),0,0,0,0,0,0,0,0,7,9,11,1,&score,&status,&job);assert(status==0&&job==1);
        // Rotations and half-pixel ties, including clipped feature coordinates.
        for(int rotation=0;rotation<8;rotation++){
            if(argc>1&&rotation!=0&&rotation!=3)continue;
            double angle=rotation*3.141592653589793/4.0;
            double c[8]={std::cos(angle),-std::sin(angle),128.5,std::sin(angle),std::cos(angle),120.5,0.0001*rotation,-0.00005*rotation};
            std::memcpy(q.grids[0].c,c,sizeof(c));int expected=fitness_all(&q,0);
            qr_fitness(memory.data(),1,width,height,stride,f.size(),c[0],c[1],c[2],c[3],c[4],c[5],c[6],c[7],7,9,11,++jobs,&score,&status,&job);
            if(status||score!=expected){std::printf("MISMATCH version=%d rotation=%d got=%d expected=%d status=%u\n",version,rotation,score,expected,status);return 1;}
        }
        if(argc==1&&version==1){
            const double xs[]={-1.5,-0.5,0.5,1.5,width-0.5,width+0.5};
            const double ys[]={-0.5,0.5,1.5,height-0.5,height+0.5};
            for(double x:xs)for(double y:ys){
                double c[8]={0,0,x,0,0,y,0,0};std::memcpy(q.grids[0].c,c,sizeof(c));
                int expected=fitness_all(&q,0);
                qr_fitness(memory.data(),1,width,height,stride,f.size(),0,0,x,0,0,y,0,0,7,9,11,++jobs,&score,&status,&job);
                assert(!status&&score==expected);
            }
        }
        qr_fitness(memory.data(),1,width,height,stride,f.size(),1,0,0,0,1,0,0,0,7,10,11,999,&score,&status,&job);assert(status==2);
    }
    std::printf("FITNESS_REFERENCE_PASS jobs=%u mode=%s\n",jobs,argc>1?"reduced-rtl":"full-csim");return 0;
}
