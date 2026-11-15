# Day 09: the day 6 Dockerfile, plus the commit hash baked into the image.
# The build hook passes the hash with --build-arg COMMIT=<hash>, and the app
# shows it on its page and in /api/info.
FROM node:26
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .

# After the COPY steps on purpose: a new commit hash changes only these cheap
# steps, so the npm install stays cached between builds.
ARG COMMIT=unknown
ENV APP_COMMIT=$COMMIT

EXPOSE 3000
CMD ["node", "server.js"]
