#include <stdio.h>
#include <cstdlib>
//BEGIN_HLS_portion
//fun=gf_setup
//argname=B_TO_J,argtype=AXI4M
//argname=J_TO_B,argtype=AXI4M
//argname=gf_setup_label0,argtype=pipeline
//argname=gf_setup_label1,argtype=pipeline
//END_HEADER
#define Modar_w 16
#define Modar_nw  65536
#define Modar_nwm1  65535

#define Modar_poly  0210013
#ifdef HLS
void gf_setup(volatile int* B_TO_J, volatile int* J_TO_B, volatile int* settings)
{
	int B_TO_J_base = *settings;
	int J_TO_B_base = *settings;
	int j,b;
	gf_setup_label0:for (j = 0; j < Modar_nw; j++)
	{
		//B_TO_J[j] = Modar_nwm1;
		*(B_TO_J+B_TO_J_base+j) = Modar_nwm1;
		//J_TO_B[j] = 0;
		*(J_TO_B+J_TO_B_base+j) = 0;
	}
	//memset(B_TO_J+B_TO_J_base, Modar_nwm1, Modar_nw);
	//memset(J_TO_B+J_TO_B_base,0, ModTOar_nw);
	b = 1;
	gf_setup_label1:for (j = 0; j < Modar_nwm1; j++) {
		//B_TO_J[b] = j;
		*(B_TO_J+B_TO_J_base+b) = j;
		//J_TO_B[j] = b;
		*(J_TO_B+J_TO_B_base+j) = b;
		b = b << 1;
		if (b & Modar_nw) b = (b ^ Modar_poly) & Modar_nwm1;
	}
}
#endif
//END_HLS_portion

//BEGIN_SW
void swrun_gf_setup(int* B_TO_J, int* J_TO_B)
{
	int j,b;
	for(j = 0; j<Modar_nw; j++)
	{
		B_TO_J[j] = Modar_nwm1;
		J_TO_B[j] = 0; 
	}
	b = 1;
	for(j = 0; j<Modar_nwm1; j++)
	{
		B_TO_J[b] = j;
		J_TO_B[j] = b;
		b = b<<1;
		if(b & Modar_nw) b = (b^Modar_poly) & Modar_nwm1;
	}
}
//END_SW

int main()
{
	//INIT_TIMER
	int* B_TO_J = (int *) malloc(sizeof(int)*Modar_nw);
  	int* J_TO_B = (int *) malloc(sizeof(int)*Modar_nw);
	//START_TIMER
	swrun_gf_setup(B_TO_J,J_TO_B);
	//END_TIMER
#ifdef RUN_ACC		
	int* B_TO_J_b = (int *) malloc(sizeof(int)*Modar_nw);
  	int* J_TO_B_b = (int *) malloc(sizeof(int)*Modar_nw);
	//RUN_HW(B_TO_J_b,J_TO_B_b)
#endif
}




