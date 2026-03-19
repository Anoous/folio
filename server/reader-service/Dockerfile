FROM node:22-slim AS build

WORKDIR /app

COPY package.json package-lock.json* reader-local.tgz* ./
RUN if [ -f reader-local.tgz ]; then \
      sed -i 's|"file:../../../reader"|"file:reader-local.tgz"|' package.json; \
      rm -f package-lock.json; \
    fi && npm install

COPY tsconfig.json ./
COPY src ./src
RUN npx tsc

FROM node:22-slim

WORKDIR /app

COPY package.json package-lock.json* reader-local.tgz* ./
RUN if [ -f reader-local.tgz ]; then \
      sed -i 's|"file:../../../reader"|"file:reader-local.tgz"|' package.json; \
      rm -f package-lock.json; \
    fi && npm install --omit=dev

COPY --from=build /app/dist ./dist

ENV NODE_ENV=production
ENV PORT=3000

USER node

EXPOSE 3000

CMD ["node", "dist/index.js"]
