#!/bin/sh
# Xcode Cloud runs this before every xcodebuild action.
#
# Xcode Cloud replaces the app's build number (CFBundleVersion) with its own
# CI_BUILD_NUMBER when it archives. StoreService treats anyone whose first
# App Store build is below 100 as a buyer of the old paid app, so an archive
# with a low build number would unlock the app for every new user.
#
# Stop any archive whose build number is too low. Fix: App Store Connect >
# Apps > Agdayo > Xcode Cloud > Settings > Build Number > Next Build Number.

set -eu

MINIMUM_BUILD=103

if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
    if [ "${CI_BUILD_NUMBER:-0}" -lt "$MINIMUM_BUILD" ]; then
        echo "error: Xcode Cloud build number ${CI_BUILD_NUMBER:-unset} is below $MINIMUM_BUILD."
        echo "error: Builds below 100 unlock the full app for free (StoreService.freeVersionFirstBuild)."
        echo "error: Set Next Build Number in App Store Connect > Xcode Cloud > Settings > Build Number."
        exit 1
    fi
    echo "Archiving build ${CI_BUILD_NUMBER} (PR ${CI_PULL_REQUEST_NUMBER:-none}, branch ${CI_BRANCH:-unknown})."
fi
