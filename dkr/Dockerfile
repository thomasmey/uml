# Use debian as base image
FROM debian:stable

# x86_64 or i386
ENV SUBARCH=x86_64
ENV SRC_DIR=linux
ENV BUILD_DIR=linux-build-uml

RUN apt update && apt install curl make gcc flex bison bc -y
RUN mkdir $SRC_DIR && mkdir $BUILD_DIR
RUN curl -L https://git.kernel.org/torvalds/t/linux-6.5-rc2.tar.gz | tar xz --strip-components=1 -C $SRC_DIR
COPY config-$SUBARCH $BUILD_DIR/.config
RUN make O=/$BUILD_DIR -C $SRC_DIR/ -j$(nproc) ARCH=um oldconfig all

# container needs: -cap-add=SYS_PTRACE --tmpfs /dev/shm:rw,nosuid,nodev
CMD [ $BUILD_DIR/linux mem=1280m umid=debian root=/dev/root rootflags=/ rootfstype=hostfs ]

