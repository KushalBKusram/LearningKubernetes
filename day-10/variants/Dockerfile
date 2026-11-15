# The day 6 Dockerfile with the base image as a build argument, so one file can
# produce the Debian-based (glibc), Debian slim and Alpine (musl) variants.
#
#   docker build --build-arg BASE=node:26-alpine -f variants/Dockerfile ../day-06/app
ARG BASE=node:26
FROM ${BASE}
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
