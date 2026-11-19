# GitHub Pages API preview

This branch preserves the locally developed UI. No BACK/ or DB/ files are changed.
Publishing requires review and merge of the PR into main; branch pushes and PR builds do not deploy.

## Pages paths after the approved merge

- Normal UI: https://track-record-shiplabhackathon.github.io/WatchDenchi_app/
- API trial: https://track-record-shiplabhackathon.github.io/WatchDenchi_app/api-preview/

The existing normal build keeps server anonymous auth enabled and server inventory disabled (the default).
Only the separate preview build sets WATCHDENCHI_ENABLE_SERVER_INVENTORY=true.
Both builds set WATCHDENCHI_API_BASE_URL=https://watchdenchi-app.onrender.com and WATCHDENCHI_ENABLE_SERVER_AUTH=true.
The workflow packages both directories in one Pages artifact; it does not deploy a preview-only artifact that would remove the normal site.
Do not deploy this branch directly to replace the existing public site. Merge only after the owner reviews the UI changes.

## Browser verification

Use a separate browser profile for trials: these paths share the same Origin and therefore browser storage, including the anonymous token.
There is no server sandbox: registering a trial battery writes to the real Go database.

1. Open the preview URL after the approved Pages deployment completes.
2. In browser developer tools, enable Network and filter by /api/.
3. With fresh profile storage, confirm POST /api/client succeeds (201). Never share the returned token.
4. Confirm GET /api/battery returns 200 using the Bearer token.
5. Register a clearly labelled trial battery in the inventory UI; confirm POST /api/battery returns 201, then GET /api/battery shows the new record.
6. Reload and confirm the same inventory loads. Authentication may reuse its stored token rather than POST again.
7. Confirm the normal URL keeps local inventory behavior.

Server inventory mode intentionally stops location changes, use-start and replacement because their APIs are not implemented.
The Go API currently ignores chemical and does not return it; the existing trial confirmation explains this limitation.
CORS preflight must allow this Origin, Authorization and Content-Type. A command-line HTTP request alone does not prove browser CORS succeeds.

## Local checks

From FRONT/:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build web --no-pub --base-href /WatchDenchi_app/ --dart-define=WATCHDENCHI_API_BASE_URL=https://watchdenchi-app.onrender.com --dart-define=WATCHDENCHI_ENABLE_SERVER_AUTH=true
flutter build web --no-pub --output build/api-preview --base-href /WatchDenchi_app/api-preview/ --dart-define=WATCHDENCHI_API_BASE_URL=https://watchdenchi-app.onrender.com --dart-define=WATCHDENCHI_ENABLE_SERVER_AUTH=true --dart-define=WATCHDENCHI_ENABLE_SERVER_INVENTORY=true
```

Analysis currently reports informational lints; --no-fatal-infos keeps warnings and errors fatal without modifying the UI to address unrelated style recommendations.
