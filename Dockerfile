FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install XFCE desktop, Chromium, Xvfb, x11vnc, and noVNC
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    wget \
    curl \
    procps \
    htop \
    nano \
    git \
    unzip \
    xfce4 \
    xfce4-terminal \
    chromium \
    fonts-liberation \
    dbus-x11 \
    libx11-dev \
    libxrender1 \
    libxtst6 \
    libxss1 \
    libnss3 \
    libasound2 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    && rm -rf /var/lib/apt/lists/*

# Install noVNC and websockify
RUN mkdir -p /opt/noVNC && \
    wget -qO- https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz | tar xz -C /opt/noVNC --strip-components=1 && \
    wget -qO- https://github.com/novnc/websockify/archive/refs/tags/v0.11.0.tar.gz | tar xz -C /opt/noVNC/utils/websockify --strip-components=1 && \
    ln -sf /opt/noVNC/utils/websockify/websockify /usr/local/bin/websockify

ENV DISPLAY=:0
ENV RESOLUTION=1280x720x24
ENV VNC_PASSWORD=debian
ENV PORT=6080

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE ${PORT}

CMD ["/start.sh"]
