#include "FullyConnectedLayer.cuh"


FullyConnectedLayer::FullyConnectedLayer(cublasHandle_t& cublas_handle_p,
                                         cudnnTensorDescriptor_t input_tensor_desc_p,
                                         size_t n_outputs_p):
        Layer(Layer_t::FullyConnected, input_tensor_desc_p, nullptr, cublas_handle_p),
        n_outp(n_outputs_p),
        _randrange(0.01f)
{
    n_inp = in_C * in_H * in_W;
    out_C = 1;
    out_N = in_N;
    out_H = 1;
    out_W = n_outp;

    checkCudnnErrors( cudnnCreateTensorDescriptor(&output_tensor_desc) );
    checkCudnnErrors( cudnnSetTensor4dDescriptor(output_tensor_desc,
                                                 CUDNN_TENSOR_NCHW,
                                                 inp_datatype,
                                                 out_N, out_C,
                                                 out_H, out_W) );

    h_weights = (float*) malloc(n_inp * n_outp * sizeof(float));
    h_bias = (float*) malloc(n_outp * sizeof(float));

    checkCudaErrors( cudaMalloc((void**) &d_weights, n_inp * n_outp * sizeof(float)) );
    checkCudaErrors( cudaMalloc((void**) &d_bias, n_outp * sizeof(float)) );
    checkCudaErrors( cudaMalloc((void**) &d_output, out_N * out_W * sizeof(float)) );

    checkCudaErrors( cudaMalloc((void**) &d_grad_w, n_inp * n_outp * sizeof(float)) );
    checkCudaErrors( cudaMalloc((void**) &d_grad_b, n_outp * sizeof(float)) );
    checkCudaErrors( cudaMalloc((void**) &d_dx, n_inp * in_N * sizeof(float)) );

    h_ones = (float*) malloc(out_W * in_N * sizeof(float));
    checkCudaErrors( cudaMalloc((void**) &d_ones, out_W * in_N *sizeof(float)) );
    std::fill_n(h_ones, out_W * in_N, 1.0f);
    checkCudaErrors( cudaMemcpy(d_ones, h_ones,
                                sizeof(float) * out_W * in_N, cudaMemcpyHostToDevice) );
}


FullyConnectedLayer::~FullyConnectedLayer() {
    free(h_weights);
    free(h_bias);
    free(h_ones);

    checkCudaErrors( cudaFree(d_weights) );
    checkCudaErrors( cudaFree(d_bias) );
    checkCudaErrors( cudaFree(d_output) );

    checkCudaErrors( cudaFree(d_grad_w) );
    checkCudaErrors( cudaFree(d_grad_b) );
    checkCudaErrors( cudaFree(d_dx) );

    checkCudaErrors( cudaFree(d_ones) );
}


void FullyConnectedLayer::init_weights_random(std::mt19937& gen){
    std::sqrt(6.0 / (in_C*in_H*in_W + out_C*out_H*out_W));
    std::uniform_real_distribution<> get_rand(-_randrange, _randrange);

    weights_length = n_inp * n_outp;
    bias_length = n_outp;

    for (ulong i = 0; i < weights_length; ++i)
        h_weights[i] = static_cast<float>(get_rand(gen));
    for (ulong i = 0; i < bias_length; ++i)
        h_bias[i] = 1.0f;

    checkCudaErrors( cudaMemcpy(d_weights, h_weights,
                                sizeof(float) * weights_length, cudaMemcpyHostToDevice) );
    checkCudaErrors( cudaMemcpy(d_bias, h_bias,
                                sizeof(float) * bias_length, cudaMemcpyHostToDevice) );
    checkCudaErrors( cudaMemset(d_output, 0, sizeof(float) * bias_length) );
    checkCudaErrors( cudaMemset(d_grad_w, 0, sizeof(float) * weights_length) );
    checkCudaErrors( cudaMemset(d_grad_b, 0, sizeof(float) * bias_length) );
    checkCudaErrors( cudaMemset(d_dx, 0, sizeof(float) * bias_length) );

}

void FullyConnectedLayer::propagate_forward(float* d_x) {
    float alpha = 1.0f;
    float beta = 0.0f;

#ifdef DEBUG
    std::cout << "fc in: " << cudaCheckNan(d_x, in_N*in_C*in_H*in_W) << std::endl;    
#endif
#ifdef DEBUG
    std::cout << "fc w: " << cudaCheckNan(d_weights, weights_length) << std::endl;
#endif
#ifdef DEBUG
    std::cout << "fc b: " << cudaCheckNan(d_bias, bias_length) << std::endl;
#endif


    checkCublasErrors(cublasSgemm(cublas_handle, CUBLAS_OP_T, CUBLAS_OP_N,
                                  n_outp, in_N, n_inp,
                                  &alpha,
                                  d_weights, n_inp,
                                  d_x, n_inp,
                                  &beta,
                                  d_output, n_outp));


    checkCublasErrors(cublasSgemm(cublas_handle, CUBLAS_OP_N, CUBLAS_OP_N,
                                  n_outp, in_N, 1,
                                  &alpha,
                                  d_bias, n_outp,
                                  d_ones, 1,
                                  &alpha,
                                  d_output, n_outp));

#ifdef DEBUG
    std::cout << "fc out: " << cudaCheckNan(d_output, out_N*out_C*out_H*out_W) << std::endl;
#endif
}


void FullyConnectedLayer::propagate_backward(float* d_dy, float* d_x, float momentum) {
    float alpha = 1.0f;
    float beta = momentum;

#ifdef DEBUG
    std::cout << "back fc in: " << cudaCheckNan(d_dy, out_N*out_C*out_H*out_W) << std::endl;
#endif

    checkCublasErrors(cublasSgemm(cublas_handle,
                                  CUBLAS_OP_N, CUBLAS_OP_T,
                                  n_inp, n_outp, in_N,
                                  &alpha,
                                  d_x, n_inp,
                                  d_dy, n_outp,
                                  &beta,
                                  d_grad_w, n_inp));

    checkCublasErrors(cublasSgemv(cublas_handle,
                                  CUBLAS_OP_N,
                                  n_outp, in_N,
                                  &alpha,
                                  d_dy, n_outp,
                                  d_ones, 1,
                                  &beta,
                                  d_grad_b, 1));

	beta = 0.0;
    checkCublasErrors(cublasSgemm(cublas_handle,
                                  CUBLAS_OP_N, CUBLAS_OP_N,
                                  n_inp, in_N, n_outp,
                                  &alpha,
                                  d_weights, n_inp,
                                  d_dy, n_outp,
                                  &beta,
                                  d_dx, n_inp));


#ifdef DEBUG
    std::cout << "back fc out: " << cudaCheckNan(d_dx, in_N*in_C*in_H*in_W) << std::endl;
#endif

#ifdef DEBUG
    std::cout << "back fc dw: " << cudaCheckNan(d_grad_w, weights_length) << std::endl;
#endif

#ifdef DEBUG
    std::cout << "back fc db: " << cudaCheckNan(d_grad_b, bias_length) << std::endl;
#endif
}

void FullyConnectedLayer::update_weights(float lr){
    float alpha = lr;

    checkCublasErrors(cublasSaxpy(cublas_handle, weights_length,
                                  &alpha, d_grad_w, 1, d_weights, 1));
    checkCublasErrors(cublasSaxpy(cublas_handle, bias_length,
                                  &alpha, d_grad_b, 1, d_bias, 1));
}

