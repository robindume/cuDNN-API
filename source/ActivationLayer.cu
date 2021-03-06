#include "ActivationLayer.cuh"

ActivationLayer::ActivationLayer(cudnnHandle_t& cudnn_handle_p,
                                 cudnnTensorDescriptor_t input_tensor_desc_p,
                                 cudnnActivationMode_t act_f_p):
        Layer(Layer_t::Activation, input_tensor_desc_p, cudnn_handle_p, nullptr),
        act_f(act_f_p)
{
    out_N = in_N;
    out_C = in_C;
    out_H = in_H;
    out_W = in_W;

    checkCudnnErrors( cudnnCreateActivationDescriptor(&act_desc) );
    checkCudnnErrors( cudnnSetActivationDescriptor(act_desc,
                                                   act_f,
                                                   CUDNN_PROPAGATE_NAN,
                                                   0.0f) );     // TODO: Add clipped relu

    checkCudnnErrors( cudnnCreateTensorDescriptor(&output_tensor_desc) );
    checkCudnnErrors( cudnnSetTensor4dDescriptor(output_tensor_desc,
                                                 CUDNN_TENSOR_NCHW,
                                                 inp_datatype,
                                                 out_N, out_C,
                                                 out_H, out_W) );

    checkCudaErrors( cudaMalloc(&d_output, sizeof(float) * out_N * out_C * out_H * out_W) );
    checkCudaErrors( cudaMalloc(&d_dx, sizeof(float) * in_N * in_C * in_H * in_W) );

}

ActivationLayer::~ActivationLayer() {
    cudnnDestroyActivationDescriptor(act_desc);
    cudnnDestroyTensorDescriptor(output_tensor_desc);

    checkCudaErrors( cudaFree(d_output) );
    checkCudaErrors( cudaFree(d_dx) );
}


void ActivationLayer::propagate_forward(float* d_x){
    float alpha = 1.0f, beta = 0.0f;

#ifdef DEBUG
    std::cout << "act in: " << cudaCheckNan(d_x, in_N*in_C*in_H*in_W) << std::endl;
#endif

    checkCudnnErrors( cudnnActivationForward(cudnn_handle,
                                             act_desc,
                                             &alpha,
                                             input_tensor_desc,
                                             d_x,
                                             &beta,
                                             output_tensor_desc,
                                             d_output) );
    
#ifdef DEBUG
    std::cout << "pool out: " << cudaCheckNan(d_output, out_N*out_C*out_H*out_W) << std::endl;
#endif
}

void ActivationLayer::propagate_backward(float* d_dy, float* d_x, float momentum){
    float alpha = 1.0f, beta = 0.0f;
    
#ifdef DEBUG
    std::cout << "back act in: " << cudaCheckNan(d_dy, out_N*out_C*out_H*out_W) << std::endl;
#endif

    checkCudnnErrors(cudnnActivationBackward(cudnn_handle,
                                             act_desc,
                                             &alpha,
                                             output_tensor_desc, d_output,
                                             output_tensor_desc, d_dy,
                                             input_tensor_desc, d_x,
                                             &beta,
                                             input_tensor_desc, d_dx));

#ifdef DEBUG
    std::cout << "back act out: " << cudaCheckNan(d_dx, in_N*in_C*in_H*in_W) << std::endl;
#endif
}

