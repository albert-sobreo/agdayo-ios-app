# Agdayo

SwiftUI iOS app (`Agdayo/`, widgets in `AgdayoWidgets/`) with a Cloudflare Worker in `worker/`.

## Versions and build numbers

- Build numbers (`CURRENT_PROJECT_VERSION`) **never reset to 1** for a new version. They only go up, across all versions: the next build is always the last one plus 1. 3.0.3 is build 102.
- Why: `StoreService.freeVersionFirstBuild` is 100. Anyone whose first App Store build (`AppTransaction.originalAppVersion`) is below 100 is treated as having bought the app when it was paid, and gets the full unlock for free. A build of 1 would unlock every new user.
- Keep `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` the same in the app and widget targets (every build configuration in `project.pbxproj`).
- Xcode Cloud archives replace the build number with its own `CI_BUILD_NUMBER` (set under App Store Connect > Xcode Cloud > Settings > Build Number). `ci_scripts/ci_pre_xcodebuild.sh` fails any archive below 103. `MARKETING_VERSION` still has to be bumped by hand after each App Store release, or uploads are rejected because that version is closed.

## Secrets

- No API keys or secrets in this public repo. Worker secrets are set with `npx wrangler secret put` (see `worker/README.md`).
