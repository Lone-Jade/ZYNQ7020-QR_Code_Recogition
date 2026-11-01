#include "qr_fitness.h"
#include "qr_fitness_tree.h"
#include <vector>
#include <cstdio>
#include <cmath>
#include <cstring>
#include <random>
#include <cassert>
#include <chrono>
#include <algorithm>
extern "C" {
#define new c04_new_value
#include "C04_IDENTIFY_REFERENCE"
#undef new
}

struct Result {
 int32_t score;uint32_t status,job,count,error,magic,abi,caps;
 uint64_t final[8];uint32_t trace[81];
};
static Result call(const std::vector<uint32_t>&memory,unsigned operation,
 unsigned width,unsigned height,unsigned cells,const double c[8],unsigned job=13,
 unsigned frame=9,unsigned roi=17,unsigned generation=19,unsigned tree_offset=0){
 Result r={};
 /* The RTL adapter serializes m_axi's declared depth, even for an operation
  * that will reject before DMA. Give it a fully allocated input allocation. */
 assert(memory.size()<=QR_FITNESS_MEMORY_WORDS);
 std::vector<uint32_t> dma(QR_FITNESS_MEMORY_WORDS,0);
 std::memcpy(dma.data(),memory.data(),memory.size()*sizeof(uint32_t));
 qr_fitness(dma.data(),operation,width,height,(width+31)/32,cells,
  c[0],c[1],c[2],c[3],c[4],c[5],c[6],c[7],7,frame,11,job,
  &r.score,&r.status,&r.job,roi,generation,tree_offset,1,&r.count,&r.error,
  r.final,r.trace,&r.magic,&r.abi,&r.caps);
 assert(r.magic==QR_FITNESS_MAGIC&&r.abi==2&&r.caps==QR_FITNESS_HW_CAPS);
 return r;
}
static uint64_t bits(double value){uint64_t result;std::memcpy(&result,&value,8);return result;}
static void cell(std::vector<uint32_t>&f,int x,int y,int w){f.push_back(unsigned(x)|(unsigned(y)<<8)|(unsigned(uint8_t(w))<<16));}
static void ring(std::vector<uint32_t>&f,int x,int y,int r,int w){for(int i=0;i<2*r;i++){
 cell(f,x-r+i,y-r,w);cell(f,x-r,y+r-i,w);cell(f,x+r,y-r+i,w);cell(f,x+r-i,y+r,w);}}
static void cap(std::vector<uint32_t>&f,int x,int y){x+=3;y+=3;cell(f,x,y,1);ring(f,x,y,1,1);ring(f,x,y,2,-1);ring(f,x,y,3,1);}
static void apat(std::vector<uint32_t>&f,int x,int y){cell(f,x,y,1);ring(f,x,y,1,-1);ring(f,x,y,2,1);}
static std::vector<uint32_t> features(int size){std::vector<uint32_t>f;
 for(int i=0;i<size-14;i++){int w=(i&1)?1:-1;cell(f,i+7,6,w);cell(f,6,i+7,w);}
 cap(f,0,0);cap(f,size-7,0);cap(f,0,size-7);
 const auto &info=quirc_version_db[(size-17)/4];int n=0;while(n<QUIRC_MAX_ALIGNMENT&&info.apat[n])n++;
 for(int i=1;i+1<n;i++){apat(f,6,info.apat[i]);apat(f,info.apat[i],6);}
 for(int i=1;i<n;i++)for(int j=1;j<n;j++)apat(f,info.apat[i],info.apat[j]);return f;
}
static void test_tree(){
 std::mt19937_64 rng(0x7021b003);uint64_t tree[QR_FITNESS_TREE_TOTAL_NODES];
 unsigned compared=0;
 for(unsigned path=0;path<5000;path++){
  double initial[8],current[8],step[8];unsigned node[8]={};
  for(unsigned i=0;i<8;i++){
   initial[i]=std::ldexp(double(int64_t(rng()%2000001)-1000000)/1000000.0,int(rng()%161)-80);
   if(path<4)initial[i]=(path&1)?-0.0:0.0;
   current[i]=initial[i];step[i]=initial[i]*0.02;
  }
  assert(qr_fitness_tree_build(initial,tree)==0);
  for(unsigned pass=0;pass<5;pass++){
   for(unsigned i=0;i<8;i++)for(unsigned sign=0;sign<2;sign++){
    double candidate=sign?current[i]+step[i]:current[i]-step[i];
    assert(tree[i*1023+node[i]]==bits(candidate));++compared;
    bool accept=rng()&1;if(accept)current[i]=candidate;
    node[i]=2*node[i]+1+(accept?1:0);
   }
   for(unsigned i=0;i<8;i++)step[i]*=0.5;
  }
 }
 double initial[8]={1,0,128,0,1,120,0.0001,0.0001};
 auto begin=std::chrono::steady_clock::now();
 for(unsigned i=0;i<500;i++)assert(!qr_fitness_tree_build(initial,tree));
 auto elapsed=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-begin).count();
 std::printf("TREE_REFERENCE_PASS paths=5000 candidates=%u host_build_mean_ns=%lld\n",compared,(long long)(elapsed/500));
}
static int reference_score(struct quirc&q,const std::vector<uint32_t>*selected){
 if(!selected)return fitness_all(&q,0);
 int result=0;for(uint32_t word:*selected)
  result+=int(int8_t(word>>16))*fitness_cell(&q,0,word&255,(word>>8)&255);
 return result;
}
static unsigned reference_optimize(struct quirc&q,double c[8],uint32_t trace[81],
                                  const std::vector<uint32_t>*selected){
 std::memcpy(q.grids[0].c,c,64);double step[8];for(unsigned i=0;i<8;i++)step[i]=c[i]*0.02;
 int best=reference_score(q,selected);trace[0]=uint32_t(best)&0x7fffffffU;unsigned count=1;
 for(unsigned pass=0;pass<5;pass++){
  for(unsigned i=0;i<8;i++)for(unsigned sign=0;sign<2;sign++){
   double old=q.grids[0].c[i];q.grids[0].c[i]=sign?old+step[i]:old-step[i];
   int test=reference_score(q,selected);bool accept=test>best;
   trace[count++]=(uint32_t(test)&0x7fffffffU)|(accept?0x80000000U:0);
   if(accept)best=test;else q.grids[0].c[i]=old;
  }
  for(unsigned i=0;i<8;i++)step[i]*=0.5;
 }
 std::memcpy(c,q.grids[0].c,64);return best;
}
int main(int argc,char**argv){
 bool reduced=argc>1,sparse=reduced&&!std::strcmp(argv[1],"rtl_sparse");
 std::mt19937 rng(702103);unsigned grids=0,scores=0;
 if(!reduced)test_tree();
 const double zero[8]={};
 for(unsigned version=1;version<=40;version++){
  if(reduced&&version!=1&&version!=20&&version!=40)continue;
  unsigned width=253+version%5,height=237+version%4,stride=(width+31)/32;
  std::vector<uint8_t> pixels(width*height);std::vector<uint32_t>roi(stride*height);
  for(unsigned y=0;y<height;y++)for(unsigned x=0;x<width;x++){
   pixels[y*width+x]=(rng()&1)?1:0;if(pixels[y*width+x])roi[y*stride+(x>>5)]|=1U<<(x&31);
  }
  auto f=features(version*4+17);assert(f.size()<=2048);
  if(sparse){
   auto full=f;f.clear();
   for(unsigned i=0;i<7;i++)f.push_back(full[i*(full.size()-1)/6]);
   auto largest=std::max_element(full.begin(),full.end(),[](uint32_t a,uint32_t b){
    return std::max(a&255,(a>>8)&255)<std::max(b&255,(b>>8)&255);
   });
   f.push_back(*largest);
   /* Both legal extreme coordinates and opposite feature weights are covered. */
   f.push_back(0U|(0U<<8)|(uint32_t(255)<<16));
   bool positive=false,negative=false;unsigned max_coordinate=0;
   for(uint32_t word:f){positive|=int8_t(word>>16)>0;negative|=int8_t(word>>16)<0;
    max_coordinate=std::max(max_coordinate,std::max(word&255,(word>>8)&255));}
   assert(positive&&negative&&max_coordinate==version*4+16);
   std::printf("RTL_SPARSE_FIXTURE version=%u cells=%zu max_coordinate=%u positive_negative=1\n",version,f.size(),max_coordinate);
  }
  auto loaded=call(roi,3,width,height,0,zero);assert(!loaded.status&&!loaded.count);
  struct quirc q={};q.w=width;q.h=height;q.pixels=pixels.data();q.num_grids=1;q.grids[0].grid_size=version*4+17;
  for(unsigned rotation=0;rotation<(reduced?1U:8U);rotation++){
   double angle=rotation*3.141592653589793/4.0;
   double initial[8]={std::cos(angle),-std::sin(angle),128.5,std::sin(angle),std::cos(angle),120.5,0.0001*(rotation+1),0.00005*(rotation+1)};
   uint64_t tree[8184];assert(!qr_fitness_tree_build(initial,tree));
   unsigned offset=f.size();std::vector<uint32_t>job(offset+QR_FITNESS_TREE_WORDS);
   std::memcpy(job.data(),f.data(),f.size()*4);std::memcpy(job.data()+offset,tree,sizeof(tree));
   double expected[8];std::memcpy(expected,initial,64);uint32_t trace[81];
   int best=reference_optimize(q,expected,trace,sparse?&f:nullptr);
   auto result=call(job,4,width,height,f.size(),initial,13+rotation,9,17,19,offset);
   if(result.status||result.score!=best||result.count!=81){
    std::printf("OPTIMIZE_FAILURE version=%u rotation=%u status=%u count=%u score=%d expected=%d\n",version,rotation,result.status,result.count,result.score,best);return 1;
   }
   for(unsigned i=0;i<8;i++)assert(result.final[i]==bits(expected[i]));
   for(unsigned i=0;i<81;i++)if(result.trace[i]!=trace[i]){
    std::printf("TRACE_FAILURE version=%u rotation=%u step=%u got=%08x expected=%08x\n",version,rotation,i,result.trace[i],trace[i]);return 1;
   }
   ++grids;scores+=81;
   if(!reduced){
    auto same=call(f,5,width,height,f.size(),initial,100+rotation);assert(!same.status);
    auto scored=call(f,1,width,height,f.size(),initial,100+rotation);
    std::memcpy(q.grids[0].c,initial,64);assert(!scored.status&&scored.count==1&&scored.score==fitness_all(&q,0));
    assert(call(f,1,width,height,f.size(),initial,101+rotation).status==2);
    assert(call(job,4,width,height,f.size(),initial,13,10,17,19,offset).status==2);
    assert(call(job,4,width,height,f.size(),initial,13,9,18,19,offset).status==2);
    assert(call(job,4,width,height,f.size(),initial,13,9,17,20,offset).status==2);
    assert(call(job,4,width,height,f.size(),initial,13,9,17,19,offset-1).status==5);
    auto corrupt=job;corrupt[0]|=0x01000000U;
    assert(call(corrupt,4,width,height,f.size(),initial,13,9,17,19,offset).status==4);
    corrupt=job;corrupt[offset]=1;corrupt[offset+1]=0;
    auto rejected=call(corrupt,4,width,height,f.size(),initial,13,9,17,19,offset);
    assert(rejected.status==3&&rejected.count==1&&rejected.error==1);
   }
   if(reduced&&version==1){
    assert(call(job,4,width,height,f.size(),initial,13,10,17,19,offset).status==2);
    assert(call(job,4,width,height,f.size(),initial,13,9,18,19,offset).status==2);
    assert(call(job,4,width,height,f.size(),initial,13,9,17,20,offset).status==2);
    assert(call(job,4,width,height,f.size(),initial,13,9,17,19,offset-1).status==5);
    auto corrupt=job;corrupt[0]|=0x01000000U;
    assert(call(corrupt,4,width,height,f.size(),initial,13,9,17,19,offset).status==4);
    double invalid[8];std::memcpy(invalid,initial,64);uint64_t subnormal=1;
    std::memcpy(invalid,&subnormal,8);
    auto rejected=call(job,4,width,height,f.size(),invalid,13,9,17,19,offset);
    assert(rejected.status==3&&rejected.count==0);
    assert(!call(f,5,width,height,f.size(),initial,100).status);
    assert(call(f,1,width,height,f.size(),initial,101).status==2);
   }
  }
  assert(!call(roi,2,width,height,0,zero).status);
  assert(call(f,1,width,height,f.size(),zero).status==2);
 }
 std::printf("WHOLE_GRID_REFERENCE_PASS grids=%u scores=%u mode=%s\n",grids,scores,sparse?"rtl-sparse-features":reduced?"full-feature-hls-model":"full-native");
 return 0;
}
