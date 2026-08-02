# The Android SDK's native Linux tools are x86-64, so the image is intentionally amd64-only.
# Pin the index for update tooling; --platform selects its amd64 image.
FROM --platform=linux/amd64 alvrme/alpine-android:android-37.0-jdk21-v2026.07.14@sha256:96a7d10aa393c817dfc6b2d60911f574223929f182eb55573bdf73121d4f5421

# The core font package supplies AWT without the unused faces in font-dejavu-extra.
RUN apk add --no-cache \
    fontconfig \
    freetype \
    libstdc++ \
    font-dejavu-core

LABEL org.opencontainers.image.title="android-ci" \
      org.opencontainers.image.description="Android build image for Kotlin Multiplatform projects" \
      org.opencontainers.image.authors="Hextremelabs" \
      org.opencontainers.image.vendor="Hextremelabs"
