FROM ubuntu:focal AS build
ENV DEBIAN_FRONTEND=noninteractive

RUN mkdir /build

# Install global build dependencies
RUN \
  apt-get update && \
  apt-get install -y \
    git \
    wget \
    pkg-config \
    libtool \
    automake \
    cmake

# Install libsrtp dev
RUN \
  apt-get install -y \
    libssl-dev


RUN cd /tmp && \
	wget https://github.com/cisco/libsrtp/archive/refs/tags/v2.4.2.tar.gz && \
	tar xfv v2.4.2.tar.gz && \
	cd libsrtp-2.4.2 && \
	./configure --prefix=/usr/local --enable-openssl && \
	make shared_library && \
	make install

# Install build dependencies of libnice
RUN \
  apt-get update && \
  apt-get install -y \
	  libssl-dev \
    libglib2.0-dev \
    python3 \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    ninja-build \
    gtk-doc-tools && \
  pip3 install meson

# Build libnice from sources as one shipped with ubuntu is a bit outdated
RUN \
  cd /build && \
  git clone --branch 0.1.21 https://gitlab.freedesktop.org/libnice/libnice.git && \
  cd libnice && \
  meson builddir && \
  ninja -C builddir && \
  ninja -C builddir install

# Build usrsctp from sources
RUN \
  cd /build && \
  git clone https://github.com/sctplab/usrsctp && \
  cd usrsctp && \
  git reset --hard 07f871bda23943c43c9e74cc54f25130459de830 && \
  cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr/local . && \
  make -j$(nproc) && \
  make install

RUN \
  cd /build && \
  git clone https://libwebsockets.org/repo/libwebsockets && \
  cd libwebsockets && \
  git checkout v4.3-stable && \
  mkdir build && \
  cd build && \
  # See https://github.com/meetecho/janus-gateway/issues/732 re: LWS_MAX_SMP
  # See https://github.com/meetecho/janus-gateway/issues/2476 re: LWS_WITHOUT_EXTENSIONS
  cmake -DLWS_MAX_SMP=1 -DLWS_WITHOUT_EXTENSIONS=0 -DCMAKE_INSTALL_PREFIX:PATH=/usr/local -DCMAKE_C_FLAGS="-fpic" .. && \
  make && make install

# Install build dependencies of janus-gateway
RUN \
  apt-get update && \
  apt-get install -y \
    libglib2.0-dev \
    libmicrohttpd-dev \
    libjansson-dev \
    libsofia-sip-ua-dev \
	libopus-dev \
    libogg-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libcurl4-openssl-dev \
    liblua5.3-dev \
	libconfig-dev \
    gengetopt

# Build janus-gateway from sources
RUN \
  cd /build && \
  git clone --branch v1.1.2 https://github.com/meetecho/janus-gateway.git

RUN cd /build/janus-gateway && \
  sh autogen.sh && \
  ./configure --prefix=/usr/local

RUN cd /build/janus-gateway && \
  make -j$(nproc) && \
  make install && \
  make configs


FROM ubuntu:focal
ENV DEBIAN_FRONTEND=noninteractive

ARG app_uid=999
ARG ulimit_nofile_soft=524288
ARG ulimit_nofile_hard=1048576

# Install runtime dependencies of janus-gateway
RUN \
  apt-get update && \
  apt-get install -y \
    nano \
    mc \
	libssl1.1 \
    libglib2.0-0 \
    libmicrohttpd12 \
    libjansson4 \
    libsofia-sip-ua-glib3 \
	libopus0 \
    libogg0 \
    libavcodec58 \
    libavformat58 \
    libavutil56 \
    libcurl4 \
    liblua5.3-0 \
	libconfig9

# Copy all things that were built
COPY --from=build /usr/local /usr/local

RUN \
  apt-get update && \
  apt-get install -y \
    nginx

# Set ulimits
RUN \
  echo ":${app_uid}	soft	nofile	${ulimit_nofile_soft}" > /etc/security/limits.conf && \
  echo ":${app_uid}	hard	nofile	${ulimit_nofile_hard}" >> /etc/security/limits.conf

# Do not run as root unless necessary
RUN groupadd -g ${app_uid} app && useradd -r -u ${app_uid} -g app app


# Start the gateway
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib/x86_64-linux-gnu

RUN cd /etc/nginx/sites-enabled/ && rm -rf

EXPOSE 10000-10200/udp
EXPOSE 8188
EXPOSE 8088
EXPOSE 8089
EXPOSE 8889
EXPOSE 8000
EXPOSE 7088
EXPOSE 7089

VOLUME /usr/local/etc/janus
VOLUME /etc/nginx/sites-enabled
VOLUME /etc/letsencrypt

STOPSIGNAL SIGTERM
COPY run.sh /run.sh
RUN chmod +x /run.sh
ENTRYPOINT ["/run.sh"]


# sudo docker run -v /home/moe/Desktop/janus/config:/usr/local/etc/janus -p 8088:8088 -p 7088:7088 janus-moe:latest