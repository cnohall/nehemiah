# Game + signaling in one container. Build from the repo root after a web export:
#   godot --headless --export-release "Web" build/web/index.html
#   docker build -f server/Dockerfile -t nehemiah .
FROM node:22-alpine
WORKDIR /app
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev
COPY server/server.js ./
COPY build/web ./web
ENV STATIC_DIR=/app/web PORT=8787
EXPOSE 8787
CMD ["node", "server.js"]
