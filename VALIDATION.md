# Validation — 7 November 2026

## Application checks

- `flutter pub get`: passed with the included lockfile.
- `dart format --output=none --set-exit-if-changed lib test`: passed (25 Dart files, no changes).
- `flutter analyze`: passed, no issues.
- `flutter test`: passed, **25 tests**.
- `flutter build apk --debug`: passed; universal debug APK built.
- `apksigner verify --verbose --print-certs`: passed; APK Signature Scheme v2, one RSA 2048-bit debug signer.
- `zipalign -c -P 16 4`: passed, including 16 KB native-library page alignment.
- APK ZIP CRC/integrity: passed.
- Package: `org.studyforge.studyforge`, version `1.0.0` (1), minimum SDK 24, target SDK 36.
- Actual packaged native ABIs: `arm64-v8a`, `armeabi-v7a`, `x86_64`.
- Actual APK size: **137,366,677 bytes** (137.4 MB / 131.0 MiB).
- SHA-256: `dd5b9a9e847d290020e5be37d7060092018b4a419a20b9063bd31e1bafe40c57`.

Build environment: Flutter 3.38.5, Dart 3.10.4, Temurin JDK 17.0.17, Android SDK 36, Build Tools 35.0.0, NDK 27.0.12077973, AGP 8.11.1 and Kotlin 2.2.20. The restricted environment blocked Flutter's Google storage host, so matching engine libraries from the downloaded Flutter SDK cache were supplied through a session-local Maven cache. The SDK-bundled embedding dependencies were used and native engine debug symbols were stripped with the Android NDK, as in normal APK packaging. Build caches/toolchain files were kept outside the delivered source. The included project and workflow use normal upstream repositories. No session proxy configuration, SDK binaries or debug signing key are bundled in the source ZIP.

Automated suite: **25 tests** across five files:

- `study_rules_test.dart` — scoring (including unanswered questions), spaced-repetition intervals and cap, topic revision thresholds, calendar/year boundaries, timer pause/resume/recovery and duplicate completion.
- `store_backup_test.dart` — SQLite create/edit/delete/search/favourites; parent edits preserving children; foreign-key cascades; saved quiz answer snapshots; persisted card reviews; idempotent focus recording; database close/reopen and schema migration; opt-in sample loading without fake activity; record/file backup round trips; invalid versions, path traversal and missing documents; transaction rollback preserving prior records and removing staged files; delete-all and orphan cleanup.
- `online_test.dart` — correctly encoded HTTPS searches, source URL validation, unavailable-service errors and empty results. These use an HTTP mock, not the live Wikipedia service.
- `reminders_test.dart` — Android platform-channel mock verifies no permission request during initialisation and explicit permission denial on opt-in. This is not an Android OS permission-dialog test.
- `widget_test.dart` — five-tab navigation and Settings at **320 logical pixels / 1.6× text**; the Home Review Cards shortcut; onboarding skip without loading samples; creating a course and note with immediate visible refresh; a Flutter-rendered dashboard screenshot using empty activity data.

The source includes `.github/workflows/android-debug.yml` for manually building and downloading the APK on GitHub Actions. That hosted workflow has not been run in this session.

## Phone checks still required

No native end-to-end phone/emulator test was performed. ADB could not initialise its default user configuration in this restricted workspace. Do these checks on the testing phone:

1. Install and launch on Android 7.0+; skip the introduction, then test a fresh install with optional samples separately.
2. Create/edit/delete a course, note, question, card, session, assignment and paper. Force-stop/reopen and confirm persistence.
3. Enable airplane mode and use saved notes, quizzes, cards, plans, progress and timers. Online search should show a recoverable connectivity message.
4. Import a real PDF through a document provider, read it, restart the app and read it again. Try cancellation, an encrypted/damaged PDF and a file over 30 MB.
5. Import a paper and a separate marking guide; save written answers, open both offline, then replace/delete attachments.
6. Deny notification permission on Android 13+, confirm planning still works, then enable permission in Android Settings. Check reminder delivery, editing/deletion, reboot and time-zone changes. OEM power saving can delay inexact reminders.
7. Start/pause/resume a focus timer; background and force-stop/reopen; confirm elapsed time and one completion record. Confirm break time is not recorded as study time.
8. Export a backup using the system save picker, restore on a fresh installation and verify PDFs, records and progress. Restore is replacement, not merging.
9. With data/Wi-Fi on, search Wikipedia, save a reference note, disable data and read that note. Open the external learning sites in a browser.
10. Test dark/system themes, a small physical screen, large text, landscape and the on-screen keyboard.

## Scope and limits

There are no accounts, cloud-sync server or automatic uploads. Online functionality is public topic search and browser links to free resources. Study records are stored locally. A shared online classroom or cloud document library is outside this build.

PDFs are not converted to questions or automatically marked. The demonstration bank is small and original. Focus completion is recorded on the app's next reconciliation; background audio is not a foreground-service alarm. The past-paper timer does not survive closing that paper screen/process. See README for scheduling, accuracy, backup-size limits and date/time behaviour.
