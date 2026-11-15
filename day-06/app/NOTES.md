# Notes for developers

This file sits in the build context on purpose. `.dockerignore` excludes `*.md`,
so it must not appear in the image. `verify.sh` checks that.

Endpoints:

- `/` a page showing the version, the container's hostname and the platform
- `/api/info` the same values as JSON
- `/health` returns 200, or 500 while the file `/tmp/unhealthy` exists (used on day 10)
