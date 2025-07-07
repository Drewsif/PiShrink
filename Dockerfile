FROM debian:stable-slim

# 1) Install PiShrink prereqs
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      e2fsprogs dosfstools parted xz-utils squashfs-tools kpartx ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# 2) Copy in PiShrink & our wrapper
COPY pishrink.sh shrink-wrapper.sh /usr/local/bin/

# 3) Fix the shebang on pishrink, rename for tidiness, and chmod both
RUN mv /usr/local/bin/pishrink.sh /usr/local/bin/pishrink \
 && mv /usr/local/bin/shrink-wrapper.sh /usr/local/bin/shrink-wrapper \
 && chmod +x /usr/local/bin/pishrink /usr/local/bin/shrink-wrapper

# — no ENTRYPOINT or CMD —
