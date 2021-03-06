//nvcc -arch=sm_30 -lcufft fft_batched.cu


#include <cuda.h>
#include <cufft.h>
#include <stdio.h>
#include <math.h>

#define DATASIZE 8
#define BATCH 3

#define GRID_DIMENSION  3
#define BLOCK_DIMENSION 3



/********************/
/* CUDA ERROR CHECK */
/********************/
#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true)
{
   if (code != cudaSuccess)
   {
      fprintf(stderr,"GPUassert: %s %s %dn", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}
__global__ void conjugate(long int nelem, cufftComplex *conj);


/********/
/* MAIN */
/********/
int main ()
{
    
    // --- Host side input data allocation and initialization
    cufftReal *hostInputData = (cufftReal*)malloc(DATASIZE*BATCH*sizeof(cufftReal));
    int grid_size  = GRID_DIMENSION;
    int block_size = BLOCK_DIMENSION;

    dim3 DimGrid(grid_size, grid_size, grid_size);
    dim3 DimBlock(block_size, block_size, block_size);


    for (int i=0; i<BATCH; i++)
        for (int j=0; j<DATASIZE; j++){ 
		hostInputData[i*DATASIZE + j] = (cufftReal)((i + 1) + j);
		printf("hostInputData[%d]=%f\n",i*DATASIZE + j,hostInputData[i*DATASIZE + j]);
	}

    // --- Device side input data allocation and initialization
    cufftReal *deviceInputData; 
    gpuErrchk(cudaMalloc((void**)&deviceInputData, DATASIZE * BATCH * sizeof(cufftReal)));

    cudaMemcpy(deviceInputData, hostInputData, DATASIZE * BATCH * sizeof(cufftReal), cudaMemcpyHostToDevice);

    // --- Host side output data allocation
    cufftComplex *hostOutputData = (cufftComplex*)malloc((DATASIZE / 2 + 1) * BATCH * sizeof(cufftComplex));

    // --- Device side output data allocation
    cufftComplex *deviceOutputData; 
    cufftComplex *fft_conj; 
    gpuErrchk(cudaMalloc((void**)&deviceOutputData, (DATASIZE / 2 + 1) * BATCH * sizeof(cufftComplex)));
    gpuErrchk(cudaMalloc((void**)&fft_conj,         (DATASIZE / 2 + 1) * BATCH * sizeof(cufftComplex)));

    // --- Batched 1D FFTs
    cufftHandle handle;
    int rank = 1;                           // --- 1D FFTs
    int n[] = { DATASIZE };                 // --- Size of the Fourier transform
    int istride = 1, ostride = 1;           // --- Distance between two successive input/output elements
    int idist = DATASIZE, odist = (DATASIZE / 2 + 1); // --- Distance between batches
    int inembed[] = { 0 };                  // --- Input size with pitch (ignored for 1D transforms)
    int onembed[] = { 0 };                  // --- Output size with pitch (ignored for 1D transforms)
    int batch = BATCH;                      // --- Number of batched executions

    printf("idist = %d\n", idist);
    printf("odist = %d\n", odist);
    printf("n = %d\n", n[0]);

    cufftPlanMany(&handle, rank, n,
                  inembed, istride, idist,
                  onembed, ostride, odist, CUFFT_R2C, batch);

    //cufftPlan1d(&handle, DATASIZE, CUFFT_R2C, BATCH);
    cufftExecR2C(handle,  deviceInputData, deviceOutputData);
    gpuErrchk(cudaMemcpy(fft_conj,       deviceOutputData, (DATASIZE / 2 + 1) * BATCH * sizeof(cufftComplex), cudaMemcpyDeviceToDevice));
    conjugate <<< DimGrid, DimBlock >>> ((DATASIZE / 2 + 1) * BATCH, fft_conj );
    // --- Device->Host copy of the results
    gpuErrchk(cudaMemcpy(hostOutputData, deviceOutputData, (DATASIZE / 2 + 1) * BATCH * sizeof(cufftComplex), cudaMemcpyDeviceToHost));

    for (int i=0; i<BATCH; i++)
        for (int j=0; j<(DATASIZE / 2 + 1); j++)
            printf("Batch  = %i j= %i real %f imag %f\n", i, j, hostOutputData[i*(DATASIZE / 2 + 1) + j].x, hostOutputData[i*(DATASIZE / 2 + 1) + j].y);

    cufftDestroy(handle);
    gpuErrchk(cudaFree(deviceOutputData));
    gpuErrchk(cudaFree(deviceInputData));
    gpuErrchk(cudaFree(fft_conj));
    cudaDeviceSynchronize();
    cudaDeviceReset();
    return EXIT_SUCCESS;

}

__global__ void conjugate(long int nelem, cufftComplex *conj)
{
int bx = blockIdx.x;
int by = blockIdx.y;
int bz = blockIdx.z;

int thx = threadIdx.x;
int thy = threadIdx.y;
int thz = threadIdx.z;

int NumThread = blockDim.x*blockDim.y*blockDim.z;
int idThread  = (thx + thy*blockDim.x) + thz*(blockDim.x*blockDim.y);
int BlockId   = (bx + by*gridDim.x) + bz*(gridDim.x*gridDim.y);

int uniqueid  = idThread + NumThread*BlockId;
if (uniqueid < nelem){
 	printf("Unique ID = %d - conj = %f\n",  uniqueid,  conj[uniqueid].y*-1);
}

//__syncthreads();
}
