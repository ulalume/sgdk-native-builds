# Release helpers shared by build.yml and sync.yml. Source from a bash step:
#   source <checkout>/.github/scripts/release-lib.sh
# Needs GH_TOKEN and GITHUB_REPOSITORY; publish_release also needs SGDK_REPO.
#
# A release is created as a DRAFT and published only once every platform bundle is attached.
# Drafts are absent from the unauthenticated /releases listing that sgdkx walks to resolve
# `--version master`, so a run that loses a platform cannot expose a release that 404s for it.
# Releases are addressed by numeric id because GET /releases/tags/<tag> never returns drafts.
#
# The functions return non-zero explicitly instead of relying on `set -e`, which bash disables
# inside a function that is called as part of an `||` / `&&` list.

RELEASE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORMS_JSON="$RELEASE_LIB_DIR/../platforms.json"

# Platform slugs, one per line. .github/platforms.json is the single list: it is also
# build.yml's build matrix, so a platform is required exactly when it is built.
platform_names() {
  jq -r '.[].name' "$PLATFORMS_JSON"
}

# Id of the release for TAG, drafts included; prints nothing if there is none.
release_id_for_tag() {
  # awk reads to EOF on purpose: exiting at the first match would kill a gh that is still
  # paginating (more than 30 releases) with SIGPIPE, and pipefail would fail the step.
  gh api --paginate "repos/$GITHUB_REPOSITORY/releases" \
      --jq ".[] | select(.tag_name == \"$1\") | .id" \
    | awk 'NR == 1'
}

# Platforms whose sgdk-<TAG>-<platform>.tar.gz is not attached to release RID, one per line.
missing_platforms() {
  local tag="$1" rid="$2" plats have p
  plats="$(platform_names)" && [ -n "$plats" ] \
    || { echo "::error::no platforms listed in $PLATFORMS_JSON" >&2; return 1; }
  have="$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases/$rid/assets" --jq '.[].name')" \
    || return 1
  for p in $plats; do
    grep -qxF "sgdk-$tag-$p.tar.gz" <<<"$have" || echo "$p"
  done
}

# Publish release RID and decide the Latest badge in the same request, so it is never briefly
# Latest with the wrong value. Only the build of the CURRENT SGDK master HEAD (master-<sha8>)
# takes it; version tags and older master builds (backfilled later by wall-clock) never do.
publish_release() {
  local tag="$1" rid="$2" head latest
  head="$(gh api "repos/${SGDK_REPO:?}/commits/master" --jq '.sha')" && [ -n "$head" ] \
    || { echo "::error::could not resolve ${SGDK_REPO} master" >&2; return 1; }
  if [ "$tag" = "master-${head:0:8}" ]; then latest=true; else latest=false; fi
  gh api --method PATCH "repos/$GITHUB_REPOSITORY/releases/$rid" \
      -F draft=false -f make_latest="$latest" >/dev/null || return 1
  echo "published $tag (make_latest=$latest)"
}

# Publish release RID if every platform bundle is attached; otherwise leave it a draft and fail.
publish_if_complete() {
  local tag="$1" rid="$2" missing
  missing="$(missing_platforms "$tag" "$rid")" || return 1
  if [ -n "$missing" ]; then
    echo "::error::$tag stays a draft -- missing platform bundle(s): $(echo $missing)" >&2
    return 1
  fi
  publish_release "$tag" "$rid"
}

# Attach FILE to release RID, replacing an asset of the same name. Each attempt first deletes
# that asset -- left by an earlier run, or stored server-side by a failed attempt -- so retrying
# the non-idempotent POST cannot fail with 422 already_exists.
upload_asset() {
  local rid="$1" file="$2" name attempt aids aid resp
  name="$(basename "$file")"
  [ -s "$file" ] || { echo "::error::asset $file is missing or empty" >&2; return 1; }
  resp="$(mktemp)"
  for attempt in 1 2 3; do
    if aids="$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases/$rid/assets" \
                 --jq ".[] | select(.name == \"$name\") | .id")"; then
      for aid in $aids; do
        gh api --method DELETE "repos/$GITHUB_REPOSITORY/releases/assets/$aid" || true
      done
      # --fail-with-body keeps GitHub's error JSON in $resp so the warning below can show it.
      if curl -sS --fail-with-body -X POST -o "$resp" \
           -H "Authorization: Bearer $GH_TOKEN" \
           -H "Accept: application/vnd.github+json" \
           -H "Content-Type: application/gzip" \
           --data-binary @"$file" \
           "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$rid/assets?name=$name"; then
        rm -f "$resp"
        echo "uploaded $name"
        return 0
      fi
      echo "::warning::upload of $name failed (attempt $attempt/3): $(cat "$resp")"
    else
      echo "::warning::listing assets of release $rid failed (attempt $attempt/3)"
    fi
    sleep $((attempt * 10))
  done
  rm -f "$resp"
  echo "::error::upload of $name failed after 3 attempts" >&2
  return 1
}
