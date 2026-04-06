FROM public.ecr.aws/docker/library/node:20-alpine

WORKDIR /app

ENV NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_PROGRESS=false

RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    procps

RUN npm install -g @nitrostack/cli --no-audit --no-fund --progress=false
