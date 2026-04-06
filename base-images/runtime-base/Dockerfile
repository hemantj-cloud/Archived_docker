FROM public.ecr.aws/docker/library/node:20-alpine

WORKDIR /app

ENV NODE_ENV=production \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_PROGRESS=false

RUN apk add --no-cache procps
RUN npm install -g @nitrostack/cli --no-audit --no-fund --progress=false

USER node

EXPOSE 3000
