FROM node:latest
WORKDIR /app
COPY package.json server.js ./
EXPOSE 3000
# Docker's own view of health (slide 315). The check is plain bash, not a new Node process,
# so it stays cheap on a busy machine. A frozen app accepts the connection but never answers,
# so the read times out and the check fails.
HEALTHCHECK --interval=3s --timeout=3s --start-period=3s --retries=3 \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/3000 && printf "GET /health HTTP/1.0\r\n\r\n" >&3 && head -1 <&3 | grep -q " 200 "'
USER node
CMD ["node", "server.js"]
