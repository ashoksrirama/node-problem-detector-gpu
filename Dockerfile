ARG NPD_TAG

FROM registry.k8s.io/node-problem-detector/node-problem-detector:${NPD_TAG}

COPY config/check_gpu.sh /config/plugin/

COPY config/gpu-monitor.json /config/

ENV NVARCH x86_64

ENV NV_CUDA_COMPAT_PACKAGE cuda-compat-12-2
ENV NVIDIA_REQUIRE_CUDA "cuda>=12.2"
ENV NV_CUDA_CUDART_VERSION 12.2.140-1

RUN apt-get update && apt-get install -y --allow-change-held-packages \
    libxml2-utils jq gnupg gnupg2 curl ca-certificates && \
    curl -fsSLO https://developer.download.nvidia.com/compute/cuda/repos/debian12/${NVARCH}/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
   # apt-get purge --autoremove -y curl \
    rm -rf /var/lib/apt/lists/*
    
RUN curl -s https://raw.githubusercontent.com/sormy/aws-curl/master/aws-curl -o /usr/local/bin/aws-curl
RUN chmod +x /usr/local/bin/aws-curl

ENV CUDA_VERSION 12.2.2

# For libraries in the cuda-compat-* package: https://docs.nvidia.com/cuda/eula/index.html#attachment-a
RUN apt-get update && apt-get install -y --no-install-recommends \
    cuda-cudart-12-2=${NV_CUDA_CUDART_VERSION} \
    ${NV_CUDA_COMPAT_PACKAGE} \
    && rm -rf /var/lib/apt/lists/*

# Required for nvidia-docker v1
RUN echo "/usr/local/nvidia/lib" >> /etc/ld.so.conf.d/nvidia.conf \
    && echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf

ENV PATH /usr/local/nvidia/bin:/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH /usr/local/nvidia/lib:/usr/local/nvidia/lib64

COPY NGC-DL-CONTAINER-LICENSE /

# nvidia-container-runtime
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES compute,utility
