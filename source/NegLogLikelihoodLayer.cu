#include "NegLogLikelihoodLayer.cuh"

NegLogLikelihoodLayer::NegLogLikelihoodLayer(cudnnHandle_t& cudnn_handle_p,
                   cudnnTensorDescriptor_t input_tensor_desc_p):
           cudnn_handle(cudnn_handle_p),
           input_tensor_desc(input_tensor_desc_p)

{
    int inp_strid;
    checkCudnnErrors( cudnnGetTensor4dDescriptor(input_tensor_desc,
                                                 &inp_datatype,
                                                 &in_N, &in_C, &in_H, &in_W,
                                                 &inp_strid, &inp_strid, &inp_strid, &inp_strid) );

    out_N = in_N;
    out_C = 1;
    out_H = 1;
    out_W = 1;

    n_labels = in_C * in_H * in_W;

    checkCudnnErrors( cudnnCreateTensorDescriptor(&output_tensor_desc) );
    checkCudnnErrors( cudnnSetTensor4dDescriptor(output_tensor_desc,
                                                 CUDNN_TENSOR_NCHW,
                                                 inp_datatype,
                                                 out_N, out_C,
                                                 out_H, out_W) );

    checkCudaErrors( cudaMalloc(&d_output, sizeof(float) * out_N * out_C * out_H * out_W) );
    checkCudaErrors( cudaMalloc(&d_dx, sizeof(float) * in_N * in_C * in_H * in_W) );
    h_output = (float *) malloc(out_N * out_W * sizeof(float));

}

NegLogLikelihoodLayer::~NegLogLikelihoodLayer() {
    cudnnDestroyTensorDescriptor(output_tensor_desc);

    free(h_output);

    checkCudaErrors( cudaFree(d_output) );
    checkCudaErrors( cudaFree(d_dx) );
}


void NegLogLikelihoodLayer::propagate_forward(float* d_t, float* d_x){

    compute_nll<<<_ceil(in_N, BW), BW>>>(d_t, d_x, n_labels, in_N, d_output);

    checkCudaErrors(cudaMemcpy(h_output, d_output,
                               out_N * out_C * out_H * out_W * sizeof(float), cudaMemcpyDeviceToHost));

    batch_loss = 0.0;
    for (uint i = 0; i < out_N; ++i) {
        batch_loss += h_output[i];
    }
}


void NegLogLikelihoodLayer::propagate_backward(float* d_t, float* d_y){

    compute_nll_loss<<<_ceil(out_N, BW), BW>>>(d_t, d_y, n_labels, in_N, d_dx);

}


__global__ void compute_nll(const float *labels,
                            const float* x,
                            int num_labels,
                            int batch_size,
                            float* losses)
{
    int batch_idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (batch_idx >= batch_size)
        return;


    int i, stride = batch_idx * num_labels;
    float loss = 0.0f;
    for (i = 0; i < num_labels; ++i){
        loss += labels[stride + i] * logf(x[stride + i]);
    }
    losses[batch_idx] = -loss;
}


__global__ void compute_nll_loss(const float *labels,
                                 const float* y,
                                 int num_labels,
                                 int batch_size,
                                 float* grad)
{
    int batch_idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (batch_idx >= batch_size)
        return;


    int i, stride = batch_idx * num_labels;
    for (i = 0; i < num_labels; ++i){
        grad[stride + i] = labels[stride + i] - y[stride + i];
    }
}