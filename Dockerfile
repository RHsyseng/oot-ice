ARG IMAGE
ARG BUILD_IMAGE

FROM ${BUILD_IMAGE} AS builder
WORKDIR /build/

ARG DRIVER_VER
ARG DRIVER_SRC
ARG KERNEL_VERSION
ARG CUSTOM_KERNEL

COPY *${CUSTOM_KERNEL} .
ENV CUSTOM_KERNEL=$CUSTOM_KERNEL
RUN if [[ ! -z ${CUSTOM_KERNEL} ]]; then \
rpm -Uvh ${CUSTOM_KERNEL}; \
fi

ADD $DRIVER_SRC/ ice-$DRIVER_VER
WORKDIR ice-$DRIVER_VER/src

RUN BUILD_KERNEL=$KERNEL_VERSION KSRC=/usr/src/kernels/$KERNEL_VERSION make

FROM ${IMAGE}

ARG DRIVER_VER
ARG KERNEL_VERSION

RUN dnf install -y kmod; dnf clean all

COPY --from=builder /build/ice-$DRIVER_VER/src/ice.ko /ice-driver/
COPY --from=builder /build/ice-$DRIVER_VER/ddp/ /ddp/
COPY scripts/load.sh scripts/unload.sh /usr/local/bin
RUN chmod +x /usr/local/bin/load.sh && chmod +x /usr/local/bin/unload.sh
