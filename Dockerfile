FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir aiohttp

COPY server.py /server.py
RUN chmod +x /server.py

EXPOSE ${PORT}

CMD python3 /server.py
