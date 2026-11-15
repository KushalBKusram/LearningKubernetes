# Day 06: the image for the Node.js app. Build it with:
#
#   docker build -t day06-app .

# Start from the official Node.js image (an image built on top of another image, slide 14).
FROM node:26

# All following instructions work in /app. WORKDIR creates it (slide 157).
WORKDIR /app

# Copy only the dependency lists first. This layer, and the install below, are
# then reused from the build cache until the dependencies change (slide 145).
COPY package.json package-lock.json ./

# Install the dependencies while building, so they are part of the image (slide 155).
RUN npm ci --omit=dev

# Copy the rest of the build context. .dockerignore decides what is left out (slide 153).
COPY . .

# Documentation only: the app listens on 3000. It still has to be published with -p (slide 151).
EXPOSE 3000

# The default program of a container made from this image, in exec form (slide 147).
CMD ["node", "server.js"]
