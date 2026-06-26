FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install XFCE desktop, Chromium, Xvfb, x11vnc, and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    wget \
    curl \
    ca-certificates \
    procps \
    htop \
    nano \
    git \
    python3 \
    python3-pip \
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

# Install websockify via pip (more reliable than downloading tarball)
RUN pip3 install --break-system-packages --no-cache-dir websockify==0.11.0

# Install noVNC (download with retry and verify)
RUN mkdir -p /opt/noVNC && \
    cd /tmp && \
    wget --tries=3 --timeout=30 -O novnc.tar.gz \
        https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz && \
    tar xzf novnc.tar.gz -C /opt/noVNC --strip-components=1 && \
    rm -f novnc.tar.gz && \
    echo "noVNC installed successfully"

# Verify installations
RUN ls /opt/noVNC/vnc.html && websockify --version

ENV DISPLAY=:0
ENV RESOLUTION=1280x720x24
ENV VNC_PASSWORD=debian
ENV PORT=6080

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE ${PORT}

CMD ["/start.sh"]
