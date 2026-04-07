# CliquePix video transcoder
# Container Apps Job that processes video transcoding requests from a Storage Queue
#
# Base image is pinned by SHA for supply-chain reproducibility.
# To update: docker pull jrottenberg/ffmpeg:6-alpine && docker inspect jrottenberg/ffmpeg:6-alpine --format '{{ index .RepoDigests 0 }}'
FROM jrottenberg/ffmpeg:6-alpine@sha256:4641478865a2387bb1d180dd9263e7226dab887c0789e02fa077fe919ef543df

# Install Node.js 20 (Alpine package) for the runner script
# Alpine's nodejs package is fine for our needs — we don't need v22+ features
RUN apk add --no-cache nodejs npm

WORKDIR /app

# Install dependencies first for better layer caching
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev --no-audit --no-fund

# Copy compiled runner code
COPY dist/ ./dist/

# Container Apps Job entrypoint
# The runner exits after processing one queue message (one job execution = one transcode)
ENTRYPOINT ["node", "dist/runner.js"]
