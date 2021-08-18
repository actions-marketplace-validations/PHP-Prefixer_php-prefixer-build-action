#!/usr/bin/env bash

set -eu

if [[ -z "$INPUT_SOURCE_DIR_PATH" ]]; then
    readonly sourceDirPath=$(pwd)
else
    readonly sourceDirPath="$INPUT_SOURCE_DIR_PATH"
fi
readonly targetDirPath=$(mktemp -d '/tmp.XXXXXXXXXX')

cat > /.env <<OUT
# Note: the .env file must be located in the php-prefixer-cli.phar directory

# Source Directory: The project source directory
SOURCE_DIRECTORY="$sourceDirPath"

# Target Directory: The target directory where the results are stored
TARGET_DIRECTORY="$targetDirPath"

# Personal Access Token: The personal access token, generated on PHP-Prefixer Settings
PERSONAL_ACCESS_TOKEN="$INPUT_PERSONAL_ACCESS_TOKEN"

# Project ID: The identification of the configured project on PHP-Prefixer Projects
PROJECT_ID="$INPUT_PROJECT_ID"

# GitHub Access Token:  An optional GitHub token to access composer.json dependencies that are managed in private repositories.
GITHUB_ACCESS_TOKEN="$INPUT_GH_PERSONAL_ACCESS_TOKEN"
OUT

initGitRepoForTargetDir() {
    rsync -avq "$sourceDirPath/.git" "$targetDirPath"

    pushd "$targetDirPath" > /dev/null

    readonly remote=tmp$(($(date +%s%N)/1000000))

    #git checkout "$INPUT_TARGET_BRANCH" || git checkout -b "$INPUT_TARGET_BRANCH"git remote add "$remote" "https://$INPUT_TARGET_REPO_USER:$GITHUB_ACCESS_TOKEN@github.com/$GITHUB_REPOSITORY"
    git remote add "$remote" "https://x-access-token:$GH_TOKEN@github.com/$GITHUB_REPOSITORY"

    git fetch "$remote"
    git checkout "$INPUT_TARGET_BRANCH" || git checkout -b "$INPUT_TARGET_BRANCH"

    git config --local user.name "$GITHUB_ACTOR"
    git config --local user.email "$GITHUB_ACTOR@users.noreply.github.com"
    git config --local --unset-all "http.https://github.com/.extraheader" || true

    # Delete everything in the $targetDirPath except the .git/
    find "$targetDirPath" -mindepth 1 -name ".git" -type d -prune -o -print0 | xargs -0 rm -rf

    popd > /dev/null # $targetDirPath
}

copyFilesFromSourceDirToTargetDir() {
    rsync -avq \
        --exclude=/.git/ \
        --exclude=vendor/ \
        --exclude=vendor_prefixed/ \
        "$sourceDirPath"/ \
        "$targetDirPath"/
        #        --exclude=node_modules/ \
}

# $dirPath: Directory path with composer.json file.
initComposerPackages() {
    pushd "$1" > /dev/null
    composer update --no-dev --no-interaction
    composer dump-autoload --classmap-authoritative --no-interaction
    popd > /dev/null
}

initGitRepoForTargetDir
initComposerPackages "$sourceDirPath"
copyFilesFromSourceDirToTargetDir
initComposerPackages "$targetDirPath"

pushd "$targetDirPath" > /dev/null

find "$targetDirPath" \( \( -name composer.json -o -name composer.lock \) -type f \) -print0 | xargs -0 rm -rf
find "$targetDirPath" \( \( -name vendor -o -name vendor_prefixed \) -type d \) -print0 | xargs -0 rm -rf

/php-prefixer-cli.phar prefix --delete-build

git add --all .
git commit --all -m "Publish prefixed build $(date '+%Y-%m-%d %H:%M:%S')"

git pull -s ours $remote "$INPUT_TARGET_BRANCH" || true # remote may not exist

git push "$remote" "$INPUT_TARGET_BRANCH":"$INPUT_TARGET_BRANCH"

popd > /dev/null # $targetDirPath
