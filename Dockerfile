FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:0
ENV RESOLUTION=1280x720x24
ENV PORT=6080

RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    x11-utils \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    wget \
    curl \
    ca-certificates \
    gnupg \
    python3 \
    python3-pip \
    fonts-liberation \
    libx11-dev \
    libxrender1 \
    libxtst6 \
    libnss3 \
    libasound2 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libu2f-udev \
    libvulkan1 \
    xdg-utils \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir websockify==0.11.0

RUN wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y -f /tmp/chrome.deb 2>/dev/null || \
    (dpkg -i /tmp/chrome.deb 2>/dev/null; apt-get install -y -f) && \
    rm -f /tmp/chrome.deb

RUN mkdir -p /opt/noVNC && \
    cd /tmp && \
    wget --tries=3 --timeout=30 -O novnc.tar.gz \
        https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz && \
    tar xzf novnc.tar.gz -C /opt/noVNC --strip-components=1 && \
    rm -f novnc.tar.gz

RUN mkdir -p /etc/opt/chrome/policies/managed && \
    printf '{\n  "ExtensionInstallForcelist": [\n    "ocgahpobhhfjgaggafmidogklgiefenj"\n  ]\n}\n' > /etc/opt/chrome/policies/managed/sports_extension.json

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE ${PORT}

CMD ["/start.sh"]
