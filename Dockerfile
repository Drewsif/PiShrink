FROM debian:bookworm

# Install requirments
RUN apt update && apt install -y wget parted gzip pigz xz-utils udev e2fsprogs && apt clean

# Setup Env
ENV LANG=C.UTF-8
ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /workdir

# Copy pishrink in
COPY pishrink.sh /usr/local/bin/pishrink
RUN chmod +x /usr/local/bin/pishrink
ENTRYPOINT [ "/usr/local/bin/pishrink" ]
