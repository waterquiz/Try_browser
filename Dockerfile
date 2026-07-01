FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget ca-certificates curl \
    git nano htop sudo \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir aiohttp

COPY server.py /server.py
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE ${PORT}

CMD ["/start.sh"]
