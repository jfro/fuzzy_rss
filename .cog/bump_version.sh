#!/bin/bash
# Updates version in mix.exs for cog pre-bump hook
# Cog provides the new version as the first argument

set -e

VERSION="${1}"

if [ -z "$VERSION" ]; then
    echo "Error: No version provided"
    exit 1
fi

# Portable sed in-place update
if sed --version >/dev/null 2>&1; then
  # GNU sed
  sed -i "s/version: \"[^\"]*\"/version: \"${VERSION}\"/" mix.exs
else
  # BSD/macOS sed
  sed -i '' "s/version: \"[^\"]*\"/version: \"${VERSION}\"/" mix.exs
fi
git add mix.exs
