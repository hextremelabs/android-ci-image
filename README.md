# android-ci-image

A small Android build image for Kotlin Multiplatform projects.

It extends [`alvrme/alpine-android`](https://github.com/alvr/alpine-android) with four packages:

- `libstdc++`, which the Kotlin/Native compiler stubs link against
- `fontconfig`, `freetype` and `font-dejavu-core`, which
  [easylauncher](https://github.com/usefulness/easylauncher-gradle-plugin) needs to render launcher
  ribbons through AWT

The base supplies Liberica JDK 21, Android platform and build-tools, Bash, Git and GNU coreutils.
It is Alpaquita Linux with glibc.

## Usage

Choose a tag from the [package page](https://github.com/orgs/hextremelabs/packages/container/package/android-ci).

```yaml
# Bitbucket Pipelines
image: ghcr.io/hextremelabs/android-ci:TAG
```

```bash
docker pull ghcr.io/hextremelabs/android-ci:TAG
```

The image is amd64-only because Google's native Linux Android SDK tools are x86-64. The upstream
arm64 variant combines an arm64 JDK with those tools and is not portable to native arm64 runners.
Docker Desktop can run this image on Apple Silicon through emulation, with a performance cost.

## Tags

Tags use `<platform>-jdk<version>-<build date>`, such as
`android-37.0-jdk21-2026.08.02`. There is deliberately no `latest` tag.

A same-day rebuild replaces that day's tag. Pin the digest shown in the workflow summary when an
immutable reference is required.

## Building and verification

Pull requests build and test the image without publishing it. A push to `main`, or a manual run
from `main`, publishes only after `smoke.sh` verifies:

- the four added packages and a loadable `libstdc++.so.6`
- independent AWT rendering through file-backed and logical fonts
- the JDK version, Android platform and executable `aapt2`
- the shell tools used by consuming pipelines

GitHub creates the first GHCR package as private; change its visibility to public after the first
successful publication.

Expectations are derived from the pinned `FROM` reference. Run the test against an image directly:

```bash
docker run --rm -e EXPECT_JDK=21 -e EXPECT_PLATFORM=android-37.0 \
  -v "$PWD/smoke.sh:/smoke.sh:ro" \
  ghcr.io/hextremelabs/android-ci:TAG sh /smoke.sh
```

The publish workflow pins its base by digest and actions by commit, emits an SPDX SBOM, and
attaches signed provenance and SBOM attestations. Verify provenance with:

```bash
gh attestation verify oci://ghcr.io/hextremelabs/android-ci:TAG \
  --repo hextremelabs/android-ci-image
```

## License

The files in this repository are licensed under [Apache-2.0](LICENSE). The image contains
separately licensed software, including the
[Android SDK](https://developer.android.com/studio/terms), BellSoft Liberica JDK and the upstream
[`alvrme/alpine-android`](https://github.com/alvr/alpine-android) image.
