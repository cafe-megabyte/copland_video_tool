#include "../core/image.h"
#include "../core/timeline.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define REQUIRE(v) do { if (!(v)) { fprintf(stderr,"Core check failed at %d\n",__LINE__); return 1; } } while(0)
int main(void) {
    uint8_t rgba[5*3*4], rgb[5*3*3], base[5*3*3], frame[5*3*3], scratch[5*3*3], out[6*4*4], bg[3];
    for (int i=0;i<15;i++) { rgba[i*4]=i*13; rgba[i*4+1]=210-i*5; rgba[i*4+2]=i*7; rgba[i*4+3]=255; }
    CoplandBox b; REQUIRE(copland_prepare_image(rgba,rgb,5,3,0,0,&b,20,0,bg));
    REQUIRE(b.x1==5 && b.y1==3 && bg[1]==210);
    CoplandTimeline t;
    REQUIRE(copland_timeline_init(&t,9,30,.1,1,5,0,NULL,0)); REQUIRE(t.total_frames==304);
    double size; REQUIRE(copland_frame_state(&t,0,&size)==0 && copland_frame_state(&t,303,&size)==2);
    REQUIRE(!copland_timeline_init(&t,NAN,30,0,0,5,0,NULL,0));
    const CoplandKeyframe keys[]={{0,5},{.23,2},{.61,1}};
    REQUIRE(!copland_timeline_init(&t,9,0,0,0,5,0,keys,3));
    uint8_t transparent[4]={0,0,0,0}, dest[3], color[3];
    REQUIRE(copland_prepare_image(transparent,dest,1,1,0,0,&b,20,0,color) && dest[0]==255);
    REQUIRE(!copland_prepare_image(transparent,dest,1,1,0,1,&b,20,0,color));
    uint8_t alpha[4]={128,32,0,128};
    color[0]=color[1]=color[2]=255;
    REQUIRE(copland_prepare_image(alpha,dest,1,1,0,0,&b,20,1,color) && dest[0]==191 && dest[1]==143);
    // Independent native fixture for all frames; browser uses the public adapter.
    FILE *f=fopen("build/internal/tests/native-frames.json","w"); REQUIRE(f);
    fprintf(f,"[\n"); int first=1;
    for(int mode=0;mode<6;mode++) {
        b=(CoplandBox){1,0,4,3}; color[0]=23;color[1]=51;color[2]=99;
        REQUIRE(copland_prepare_image(rgba,rgb,5,3,0,mode==5?1:2,&b,20,1,color));
        copland_make_base(rgb,base,5,3,b,color);
        REQUIRE(copland_timeline_init(&t,.61,29.97,.05,.1,5,(CoplandEasing)(mode%4),mode==4?keys:NULL,mode==4?3:0));
        for(int i=0;i<t.total_frames;i++) {
            int state=copland_frame_state(&t,i,&size); const uint8_t *pixels=state==0?base:rgb;
            if(state==1) {
                if(!t.keyframe_count && size<=16) copland_render_smooth_frame(rgb,base,frame,scratch,5,3,b,size);
                else copland_render_frame(rgb,base,frame,5,3,b,(int)lrint(size));
                pixels=frame;
            }
            copland_pack_rgba(pixels,out,5,3,color);
            if(!first) fprintf(f,",\n"); first=0;
            fprintf(f,"{\"mode\":%d,\"index\":%d,\"count\":%d,\"hex\":\"",mode,i,t.total_frames);
            for(size_t j=0;j<sizeof(out);j++) fprintf(f,"%02x",out[j]); fprintf(f,"\"}");
        }
    }
    fprintf(f,"\n]\n"); fclose(f); puts("Native core: alpha, regions, timeline and native reference frames passed."); return 0;
}
