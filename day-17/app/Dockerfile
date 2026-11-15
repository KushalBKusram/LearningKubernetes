# A small PHP page on the official php image (slide 341 calls building your
# own image on top of the php base image "the best way").
FROM php:apache

# The version is baked in at build time, so v1 and v2 are two different images.
ARG VERSION=v1
ENV APP_VERSION=${VERSION}

COPY index.php whoami.php health.php /var/www/html/
