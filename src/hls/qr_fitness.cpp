#include "qr_fitness.h"
#include <ap_int.h>

union binary64 { double value; uint64_t bits; };

static int round_even(double x) {
    int value=(int)x;
    double fraction=x-(double)value;
    if(fraction>0.5 || (fraction==0.5 && (value&1)))++value;
    if(fraction< -0.5 || (fraction== -0.5 && (value&1)))--value;
    return value;
}

/* Bit-only restrictions match the driver and avoid PG060 subnormal flushing. */
static bool safe_coefficient(uint64_t bits,unsigned index,uint64_t negative_limit) {
#pragma HLS INLINE
    unsigned exponent=(bits>>52)&2047;
    uint64_t magnitude=bits&0x7fffffffffffffffULL;
    if(exponent==2047 || (magnitude&&(exponent<923||exponent>1122)))return false;
    return !(index>=6 && (bits>>63) && magnitude>negative_limit);
}

/* Exactly one copy is shared by legacy SCORE and all 81 optimizer evaluations.
 * Keep this II=2 pipeline and its binary64 expression order equal to R2 II=2. */
static int score_resident(const uint32_t roi[QR_FITNESS_ROI_WORDS],
 const uint32_t feature[QR_FITNESS_CELLS],uint32_t resident_width,
 uint32_t resident_height,uint32_t resident_stride,uint32_t resident_cells,
 const double c[8]) {
#pragma HLS INLINE
#pragma HLS ARRAY_PARTITION variable=c complete dim=1
    const double c0=c[0],c1=c[1],c2=c[2],c3=c[3];
    const double c4=c[4],c5=c[5],c6=c[6],c7=c[7];
    int total=0;
    const double offsets[3]={0.3,0.5,0.7};
    for(uint32_t cell=0;cell<resident_cells;cell++){
#pragma HLS LOOP_TRIPCOUNT min=161 max=1623 avg=202
        uint32_t word=feature[cell];
        unsigned x=word&255,y=(word>>8)&255;
        int weight=(int8_t)(word>>16);
        for(unsigned k=0;k<9;k++){
#pragma HLS PIPELINE II=2
            double u=(double)x+offsets[k%3];
            double v=(double)y+offsets[k/3];
            double denominator=(c6*u+c7*v)+1.0;
            double reciprocal=1.0/denominator;
            double px=((c0*u+c1*v)+c2)*reciprocal;
            double py=((c3*u+c4*v)+c5)*reciprocal;
            if(px>= -1.0 && px<=(double)resident_width && py>= -1.0 && py<=(double)resident_height){
                int ix=round_even(px),iy=round_even(py);
                if(ix>=0&&iy>=0&&ix<(int)resident_width&&iy<(int)resident_height){
                    unsigned bit=(roi[iy*resident_stride+(unsigned(ix)>>5)]>>(ix&31))&1;
                    total+=bit?weight:-weight;
                }
            }
        }
    }
    return total;
}

void qr_fitness(const uint32_t *memory,uint32_t operation,
 uint32_t width,uint32_t height,uint32_t stride_words,uint32_t cells,
 double c0,double c1,double c2,double c3,double c4,double c5,double c6,double c7,
 uint32_t epoch,uint32_t frame,uint32_t config,uint32_t job_id,
 int32_t *score,uint32_t *status,uint32_t *completed_job,
 uint32_t roi_id,uint32_t binary_generation,uint32_t tree_word_offset,
 uint32_t trace_enable,uint32_t *score_count,uint32_t *error_step,
 uint64_t result_coefficients[8],uint32_t trace[81],
 uint32_t *hardware_magic,uint32_t *hardware_abi,uint32_t *hardware_caps) {
#pragma HLS INTERFACE m_axi port=memory offset=slave bundle=memory depth=30848 max_read_burst_length=64 num_read_outstanding=2
#pragma HLS INTERFACE s_axilite port=return bundle=control
#pragma HLS INTERFACE s_axilite port=memory bundle=control
#pragma HLS INTERFACE s_axilite port=operation bundle=control
#pragma HLS INTERFACE s_axilite port=width bundle=control
#pragma HLS INTERFACE s_axilite port=height bundle=control
#pragma HLS INTERFACE s_axilite port=stride_words bundle=control
#pragma HLS INTERFACE s_axilite port=cells bundle=control
#pragma HLS INTERFACE s_axilite port=c0 bundle=control
#pragma HLS INTERFACE s_axilite port=c1 bundle=control
#pragma HLS INTERFACE s_axilite port=c2 bundle=control
#pragma HLS INTERFACE s_axilite port=c3 bundle=control
#pragma HLS INTERFACE s_axilite port=c4 bundle=control
#pragma HLS INTERFACE s_axilite port=c5 bundle=control
#pragma HLS INTERFACE s_axilite port=c6 bundle=control
#pragma HLS INTERFACE s_axilite port=c7 bundle=control
#pragma HLS INTERFACE s_axilite port=epoch bundle=control
#pragma HLS INTERFACE s_axilite port=frame bundle=control
#pragma HLS INTERFACE s_axilite port=config bundle=control
#pragma HLS INTERFACE s_axilite port=job_id bundle=control
#pragma HLS INTERFACE s_axilite port=score bundle=control
#pragma HLS INTERFACE s_axilite port=status bundle=control
#pragma HLS INTERFACE s_axilite port=completed_job bundle=control
#pragma HLS INTERFACE s_axilite port=roi_id bundle=control
#pragma HLS INTERFACE s_axilite port=binary_generation bundle=control
#pragma HLS INTERFACE s_axilite port=tree_word_offset bundle=control
#pragma HLS INTERFACE s_axilite port=trace_enable bundle=control
#pragma HLS INTERFACE s_axilite port=score_count bundle=control
#pragma HLS INTERFACE s_axilite port=error_step bundle=control
#pragma HLS INTERFACE s_axilite port=result_coefficients bundle=control
#pragma HLS INTERFACE s_axilite port=trace bundle=control
#pragma HLS INTERFACE s_axilite port=hardware_magic bundle=control
#pragma HLS INTERFACE s_axilite port=hardware_abi bundle=control
#pragma HLS INTERFACE s_axilite port=hardware_caps bundle=control
    static uint32_t roi[QR_FITNESS_ROI_WORDS];
    static uint32_t feature[QR_FITNESS_CELLS];
#pragma HLS BIND_STORAGE variable=roi type=ram_1p impl=bram
#pragma HLS BIND_STORAGE variable=feature type=ram_1p impl=bram
    static ap_uint<11> resident_width;
    static ap_uint<10> resident_height;
    static ap_uint<6> resident_stride;
    static ap_uint<12> resident_cells;
    static ap_uint<15> resident_words;
    static uint32_t resident_epoch,resident_frame,resident_config,resident_job;
    static uint32_t resident_roi,resident_generation;
    static uint64_t negative_limit;
    static bool roi_valid=false,grid_valid=false,strict_grid_tag=false;
    *score=0;*status=0;*completed_job=job_id;*score_count=0;*error_step=0;
    *hardware_magic=QR_FITNESS_MAGIC;*hardware_abi=QR_FITNESS_HW_ABI;
    *hardware_caps=QR_FITNESS_HW_CAPS;
    const double initial[8]={c0,c1,c2,c3,c4,c5,c6,c7};
#pragma HLS ARRAY_PARTITION variable=initial complete dim=1
    uint64_t coefficients[8];
#pragma HLS BIND_STORAGE variable=coefficients type=ram_1p impl=lutram
    for(unsigned i=0;i<8;i++){
        binary64 value;value.value=initial[i];coefficients[i]=value.bits;
    }
    if(operation==QR_FITNESS_INVALIDATE){roi_valid=false;grid_valid=false;return;}
    if(operation==QR_FITNESS_LEGACY_LOAD||operation==QR_FITNESS_LOAD_ROI){
        roi_valid=false;grid_valid=false;
        if(!width||width>1280||!height||height>720||stride_words!=(width+31)/32){*status=1;return;}
        ap_uint<15> words=stride_words*height;
        for(ap_uint<15> i=0;i<words;i++){
#pragma HLS PIPELINE II=1
            roi[i]=memory[i];
        }
        resident_width=width;resident_height=height;resident_stride=stride_words;
        resident_words=words;
        resident_epoch=epoch;resident_frame=frame;resident_config=config;
        resident_roi=roi_id;resident_generation=binary_generation;roi_valid=true;
        if(operation==QR_FITNESS_LOAD_ROI)return;
    }else if(!roi_valid||epoch!=resident_epoch||frame!=resident_frame||config!=resident_config||
             roi_id!=resident_roi||binary_generation!=resident_generation){*status=2;return;}

    if(operation==QR_FITNESS_LEGACY_LOAD||operation==QR_FITNESS_LOAD_GRID||operation==QR_FITNESS_OPTIMIZE){
        grid_valid=false;
        if(!cells||cells>QR_FITNESS_CELLS||!job_id){*status=1;return;}
        if(operation==QR_FITNESS_OPTIMIZE &&
           (tree_word_offset<cells||
            tree_word_offset>QR_FITNESS_MEMORY_WORDS-QR_FITNESS_TREE_WORDS)){*status=5;return;}
        ap_uint<15> offset=operation==QR_FITNESS_LEGACY_LOAD?resident_words:ap_uint<15>(0);
        ap_uint<9> max_coordinate=1;
        bool bad=false;
        for(ap_uint<12> i=0;i<ap_uint<12>(cells);i++){
#pragma HLS PIPELINE II=1
            uint32_t word=memory[offset+i];
            ap_uint<8> x=word&255,y=(word>>8)&255;
            int weight=(int8_t)(word>>16);
            if(x>=177||y>=177||(word>>24)||(weight!=1&&weight!=-1))bad=true;
            if(ap_uint<9>(x)+1>max_coordinate)max_coordinate=ap_uint<9>(x)+1;
            if(ap_uint<9>(y)+1>max_coordinate)max_coordinate=ap_uint<9>(y)+1;
            feature[i]=word;
        }
        if(bad){*status=4;return;}
        ap_uint<4> fls=0;ap_uint<10> n=4*max_coordinate-1;
        for(unsigned bit=0;bit<10;bit++){
#pragma HLS UNROLL
            if(n>>bit)fls=bit+1;
        }
        negative_limit=(uint64_t)(1023-fls)<<52;
        resident_cells=cells;resident_job=job_id;grid_valid=true;
        strict_grid_tag=operation!=QR_FITNESS_LEGACY_LOAD;
        if(operation!=QR_FITNESS_OPTIMIZE)return;
    }else if(operation!=QR_FITNESS_LEGACY_SCORE||!grid_valid||
             (strict_grid_tag&&job_id!=resident_job)){*status=2;return;}

    ap_uint<11> node[8];
#pragma HLS BIND_STORAGE variable=node type=ram_1p impl=lutram
    for(unsigned i=0;i<8;i++){
        node[i]=0;
        if(!safe_coefficient(coefficients[i],i,negative_limit)){*status=3;return;}
    }
    unsigned evaluations=operation==QR_FITNESS_OPTIMIZE?81:1;
    int best=0;
    for(unsigned step=0;step<evaluations;step++){
#pragma HLS LOOP_TRIPCOUNT min=1 max=81 avg=81
        ap_uint<3> coefficient=step?((step-1)%16)/2:0;
        uint64_t old=coefficients[coefficient];
        if(step){
            /* 2*1023 is shift/subtract, never an inferred integer DSP. */
            unsigned address=tree_word_offset+((unsigned(coefficient)<<11)-(unsigned(coefficient)<<1))+(unsigned(node[coefficient])<<1);
            binary64 trial;trial.bits=uint64_t(memory[address])|(uint64_t(memory[address+1])<<32);
            if(!safe_coefficient(trial.bits,coefficient,negative_limit)){
                *status=3;*error_step=step;return;
            }
            coefficients[coefficient]=trial.bits;
        }
        double c[8];
#pragma HLS ARRAY_PARTITION variable=c complete dim=1
        for(unsigned i=0;i<8;i++){
            binary64 value;value.bits=coefficients[i];c[i]=value.value;
        }
        int test=score_resident(roi,feature,resident_width,resident_height,
                                resident_stride,resident_cells,c);
        bool accept=step&&test>best;
        if(!step||accept)best=test;
        else coefficients[coefficient]=old;
        if(step)node[coefficient]=2*node[coefficient]+1+(accept?1:0);
        if(trace_enable)trace[step]=(uint32_t(test)&0x7fffffffU)|(accept?0x80000000U:0);
        *score_count=step+1;
    }
    *score=best;
    for(unsigned i=0;i<8;i++){
#pragma HLS PIPELINE II=1
        result_coefficients[i]=coefficients[i];
    }
}
