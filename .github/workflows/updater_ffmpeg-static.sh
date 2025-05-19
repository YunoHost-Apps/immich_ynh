#!/bin/bash

#=================================================
# FETCHING LATEST SHA256SUM
#=================================================

# Fetching information
version_current=$(cat manifest.toml | tomlq -j '.version')
# version_app=$(cat manifest.toml | tomlq -j '.version|split("~ynh")[0]')
# version_ynh=$(cat manifest.toml | tomlq -j '.version|split("~ynh")[1]')
# version_next="$version_app~ynh$(($version_ynh+1))"
# version=$(echo "$version_next" | tr '~' '-')
version=$(echo "$version_current" | tr '~' '-')
repo=$(cat manifest.toml | tomlq -j '.upstream.code|split("https://github.com/")[1]')

amd64_url=$(cat manifest.toml | tomlq -j '.resources.sources."ffmpeg-static".amd64.url')
amd64_sha_current=$(cat manifest.toml | tomlq -j '.resources.sources."ffmpeg-static".amd64.sha256')
amd64_sha_last=$(curl -fsSL --retry 3 "$amd64_url" | sha256sum - | cut -d " " -f1)

arm64_url=$(cat manifest.toml | tomlq -j '.resources.sources."ffmpeg-static".arm64.url')
arm64_sha_current=$(cat manifest.toml | tomlq -j '.resources.sources."ffmpeg-static".arm64.sha256')
arm64_sha_last=$(curl -fsSL --retry 3 "$arm64_url" | sha256sum - | cut -d " " -f1)
# For the time being, let's assume the script will fail
echo "PROCEED=false" >> $GITHUB_ENV

# Proceed only if the retrieved version is greater than the current one
if [ "$amd64_sha_current" == "$amd64_sha_last" ] && [ "$arm64_sha_current" == "$arm64_sha_last" ]
then
    echo "::warning ::No new version available"
    exit 0
# Proceed only if a PR for this new version does not already exist
elif git ls-remote -q --exit-code --heads https://github.com/$GITHUB_REPOSITORY.git ci-auto-update-ffmpeg-static-sha-$version
then
    echo "::warning ::A branch already exists for this update"
    exit 0
fi

# Print some infos
echo "Current version: $version_current"
echo "Current ffmpeg-static amd64 sha : $amd64_sha_current"
echo "Last ffmpeg-static amd64 sha : $amd64_sha_last"
echo "Current ffmpeg-static arm64 sha : $arm64_sha_current"
echo "Last ffmpeg-static arm64 sha : $arm64_sha_last"
# echo "Latest version: $version_next"

# Setting up the environment variables
echo "VERSION=$version" >> $GITHUB_ENV
echo "REPO=$repo" >> $GITHUB_ENV

#=================================================
# GENERIC FINALIZATION
#=================================================

# Replace new version in manifest
# sed -i "s/^version = .*/version = \"$version_next\"/" manifest.toml

# Replace sha356sum in manifest
sed -i "s@^\"amd64.sha256\" = .*@\"amd64.sha256\" = \"$amd64_sha_last\"@" manifest.toml
sed -i "s@^\"arm64.sha256\" = .*@\"arm64.sha256\" = \"$arm64_sha_last\"@" manifest.toml

# The Action will proceed only if the PROCEED environment variable is set to true
echo "PROCEED=true" >> $GITHUB_ENV
exit 0
