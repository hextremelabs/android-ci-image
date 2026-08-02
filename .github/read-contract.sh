#!/usr/bin/env bash
set -euo pipefail

dockerfile=${1:-Dockerfile}

from_line=$(sed -n '/^FROM .*alvrme\/alpine-android:/p' "$dockerfile")
from_pattern='^FROM[[:space:]]+--platform=([^[:space:]]+)[[:space:]]+alvrme/alpine-android:([^[:space:]]+)$'
[[ "$from_line" =~ $from_pattern ]] || { echo "could not read the base image from $dockerfile" >&2; exit 1; }

target=${BASH_REMATCH[1]}
base_ref=${BASH_REMATCH[2]}
[[ "$base_ref" == *@sha256:* ]] || { echo "base image is not pinned by digest: $base_ref" >&2; exit 1; }

base=${base_ref%%@*}
index_digest=${base_ref##*@}
[[ "$target" =~ ^[a-z0-9]+/[a-z0-9_]+$ ]] || { echo "invalid base platform: $target" >&2; exit 1; }
[[ "$base" =~ ^android-[0-9]+(\.[0-9]+)*-jdk[0-9]+-v[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]] || {
    echo "invalid base tag: $base" >&2
    exit 1
}
[[ "$index_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "invalid base digest: $index_digest" >&2; exit 1; }

base_name="docker.io/alvrme/alpine-android:$base"
target_os=${target%%/*}
target_arch=${target#*/}

# Retry transient registry failures; malformed indexes fail during parsing below.
fetch_index() {
    local attempt output
    for attempt in 1 2 3; do
        if output=$(docker buildx imagetools inspect --raw "$1"); then
            printf '%s' "$output"
            return 0
        fi
        [[ $attempt -lt 3 ]] || return 1
        echo "registry inspect failed (attempt $attempt of 3), retrying" >&2
        sleep $((attempt * 3))
    done
}

raw_index=$(fetch_index "$base_name@$index_digest") ||
    { echo "could not inspect $base_name@$index_digest after 3 attempts" >&2; exit 1; }

# OCI base.digest identifies the selected image manifest, not its multi-platform index.
base_digest=$(
    printf '%s' "$raw_index" |
        jq -er --arg os "$target_os" --arg arch "$target_arch" '
            (.manifests // error("pinned digest is not a multi-platform index; pin the digest the tag resolves to"))
            | [.[]
                | select(.platform.os == $os and .platform.architecture == $arch)
                | .digest]
            | if length == 1 then .[0]
              else error("index has no unique \($os)/\($arch) manifest; found \(length)")
              end
        '
)
[[ "$base_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "invalid platform manifest digest: $base_digest" >&2; exit 1; }

echo "base_name=$base_name"
echo "base_digest=$base_digest"
echo "platform=${base%%-jdk*}"
jdk=${base#*-jdk}
echo "jdk=${jdk%%-*}"
echo "tag=${base%-v*}-$(date -u +%Y.%m.%d)"

owner=$(printf '%s' "${GITHUB_REPOSITORY_OWNER:-}" | tr '[:upper:]' '[:lower:]')
if [[ -n "$owner" ]]; then
    [[ "$owner" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "invalid repository owner: $owner" >&2; exit 1; }
    echo "image=ghcr.io/$owner/android-ci"
fi
