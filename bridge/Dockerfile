FROM python:3.12-slim-bookworm
ENV PYTHONUNBUFFERED=1 TZ=Europe/Berlin PIP_DISABLE_PIP_VERSION_CHECK=1
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ffmpeg curl ca-certificates tzdata nodejs npm jq unzip \
 && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
 && python -m playwright install --with-deps chromium \
 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
WORKDIR /data/work
ENTRYPOINT ["/entrypoint.sh"]
