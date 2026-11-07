# StudyForge

A Flutter Android study app for university students, with account-free online reference search and persistent offline study tools. No sign-in, sign-up, backend, subscriptions, API keys, AI, advertising or analytics. Internet access is needed only for online reference search and external resource websites. Normal mobile-data charges may apply.

## Download the APK from this repository

Open [Build StudyForge testing APK](https://github.com/Clolan34/andriod-voicebot/actions/workflows/android-debug.yml), select the latest successful run, and scroll to **Artifacts**. Download **StudyForge-debug** and extract its ZIP to get `StudyForge-debug.apk`. GitHub requires you to be signed in to download Actions artifacts; StudyForge itself has no sign-in or sign-up.

A build starts automatically when source is pushed to `main`. You can also choose **Run workflow** on that page to build manually. If a run is still in progress, wait for its green check mark. These are testing APKs, not Play Store releases. Each runner may use a different debug signing key, so back up data before replacing an existing installation if Android reports a signing conflict.

## Install the testing APK

1. Download `StudyForge-debug.apk` to your Android phone.
2. Open it from Downloads. If Android asks, temporarily allow that browser or file manager to **install unknown apps**.
3. Choose Install, then open StudyForge. You can turn off the unknown-app installation permission afterward.
4. Skip the introduction or enter a name. Create your own course or explicitly load demonstration content.

Android **7.0 / API 24 or newer**. The universal debug APK targets **armeabi-v7a, arm64-v8a and x86_64**. Debug builds are larger and slower than production releases. This APK is for testing, not Play Store publication. Back up before uninstalling: uninstalling deletes app-private records and PDFs. Installing another build with a different debug signing certificate may require uninstalling the existing build.

## Features

- Home: optional local greeting, today's sessions, pending/overdue assignments, due-card count, real recent quiz results and quick actions.
- Courses: create/edit/delete, colour, course code and comma-separated topics. Course notes support content/title search, favourites, text and private offline PDFs.
- Planner: agenda and seven-day timetable, sessions with actual completed minutes, assignments with priority and completion, optional approximate local reminders.
- Practice: course/topic filters, editable four-option questions, timed/untimed quizzes, answer explanations and durable attempt snapshots. Previously incorrect practice uses the **latest saved answer** to each question. Three original demonstration questions and three cards load only when requested.
- Flashcards: reveal and grade, persisted due dates and review history.
- Past papers: user-imported PDFs, year/semester, separately linked marking guides, offline reader, a 60-minute optional practice clock, saved written answers and self-assessment. No bundled examination papers or automatic marking.
- Progress: real completed plan/focus counts, recorded minutes, quiz accuracy, flashcard review counts, course and topic accuracy, full quiz answer history.
- Focus: configurable study/rest durations (25/5 minutes by default), pause/resume/reset, background-safe deadlines and idempotent completion. Optional sound and haptics.
- Settings: local profile, system/light/dark appearance, reminder preferences, versioned ZIP backup and atomic replacement restore, confirmed deletion.
- **Learn online** (Home and Practice): Wikipedia topic search, attributed summaries saved as offline course notes, and links to Khan Academy, OpenStax, MIT OpenCourseWare and freeCodeCamp. Resource links open in the device browser. Search does not generate questions or extract PDF contents. Check reference summaries against your course materials.

## Run, test and rebuild

Install Flutter **3.38.5 / Dart 3.10.4**, Java 17 or 21, Android SDK command-line tools, Android SDK Platform 36, Build Tools 36.0.0 and NDK 27.0.12077973. Accept Android licences with `flutter doctor --android-licenses`. Android Studio can install these packages. Linux host database tests use `libsqlite3.so.0` (`libsqlite3-0` on Ubuntu/Debian). The host SQLite package is only for tests; Android uses `sqflite` and the OS SQLite implementation.

```sh
flutter doctor -v
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

The APK is at `build/app/outputs/flutter-apk/app-debug.apk`. Rename/copy it to `StudyForge-debug.apk` for sharing. Keep `pubspec.lock` to reproduce resolved dependencies. The pinned path-provider Android implementation uses platform channels, avoiding an unnecessary native JNI build dependency. Generated SDK paths in `android/local.properties` are intentionally excluded; Flutter creates that file locally. Android plugin build-script toolchains are aligned to AGP 8.11.1 and Kotlin 2.2.20 to avoid redundant compiler downloads. Gradle may download build dependencies during the first build. No session proxy settings or SDK binaries are included in the source ZIP.

Optional smaller architecture-specific debug packages:

```sh
flutter build apk --debug --split-per-abi
```

### GitHub Actions alternative

Create a GitHub repository and upload the **contents** of this source project at its root, including `.github/workflows/android-debug.yml`. Open **Actions → Build StudyForge testing APK → Run workflow**. After success, open the run and download the **StudyForge-debug** artifact. Extract the ZIP to get the APK, byte count and SHA-256 checksum. The workflow does not publish the app or require service credentials. GitHub-hosted runner usage is subject to your account's included Actions allowance.

## Architecture

```
lib/
  main.dart                 Application startup, introduction and five-tab shell
  application.dart          Shared application state and lifecycle reconciliation
  domain/study_rules.dart   Pure scoring, scheduling, timer and calendar rules
  data/models.dart          Course and study-entry models
  data/store.dart           SQLite queries, transactions, migrations and sample seed
  data/files.dart           Android picker import and private PDF lifecycle
  data/backup.dart          Versioned archive validation, staged files, atomic restore
  data/reminders.dart       Permission-on-opt-in and stable-ID rescheduling
  data/online.dart          Public reference search with bounded result size/timeout
  ui/                       Screens, editors, reusable widgets and theme
```

The database schema is version 2. Version 1 to 2 adds query indexes. Foreign keys are enabled on every connection. Courses own notes, plans, questions, cards and papers through cascading foreign keys. `entries` uses a small JSON feature-metadata envelope plus indexed relational course/type columns. Answer snapshots preserve explanations when a question is edited or deleted. Deleting a course removes its course-level answers/reviews; aggregate historical attempt scores remain. Course updates use UPDATE rather than SQLite REPLACE so child rows are preserved.

Every user database value is supplied with SQL parameters. Sample content does not create attempts, review activity or completed time. UI refreshes after committed changes. SQLite queries are asynchronous and indexed by course/type and course/topic. PDF imports are limited to **30 MB each** for modest-memory devices.

## Documented study rules

### Flashcards

Each card stores `due`, integer `interval` days and a review count:

| Rating | Next review |
| --- | --- |
| Again | 10 minutes; interval resets to 0 |
| Hard | max(1, round(previous days × 1.2)) days |
| Good | max(1, round(previous days × 2)) days |
| Easy | max(4, round(previous days × 3)) days |

Intervals cap at 365 days. This is a simple transparent algorithm, not SM-2 or a claim of personalised learning optimisation. A review batch shows each initially due card once; an Again card reappears in the next batch when its 10-minute delay has elapsed.

### Accuracy and revision

Each submitted quiz answer contributes one observation, including unanswered questions as incorrect. Topic accuracy is `correct / total` over saved answers. Fewer than **5 answers** means **Not enough data**; with at least 5, accuracy **below 60%** means **Needs revision**, otherwise **On track**. Repeated attempts count as repeated observations. Accuracy is not a university grade prediction. Study minutes are the user's explicitly recorded completed-plan minutes plus completed study focus durations. Rest periods and past-paper practice clocks do not add focus minutes.

### Dates, reminders and timers

Planner dates are selected in local time, stored as UTC instants and displayed in the current device time zone. A time-zone change preserves the instant rather than moving the appointment to the same wall-clock time. Reminders are rebuilt after plan changes, restore and app resume; all existing reminder jobs are cancelled before stable-ID replacements are installed. Android's boot receiver restores scheduled jobs after reboot. Inexact scheduling avoids exact-alarm permission, and Android/OEM power-saving restrictions may delay delivery. Notification permission is requested **only when the user enables reminders**. If denied, planning continues and the app explains the Android Settings path.

Focus clocks persist a unique session ID, deadline or paused remaining seconds, configured duration and recorded state. Remaining time is derived from the clock, not from tick counts. Completion is reconciled on startup/resume or while the timer screen is active. A unique database primary key prevents duplicate completion records after interruption/recovery. Moving the system clock manually can affect a deadline. Sounds/haptics occur while the app is active or on its next completion check; this is not a foreground-service alarm. Past-paper practice clocks survive backgrounding and opening the PDF reader but reset if that paper screen is closed or the process is killed.

## Backup and file integrity

Backup ZIP format 1 contains `manifest.json` (`format: StudyForge`, `version: 1`, schema table snapshots) and referenced `files/<private-name>.pdf` files. Import checks the version, table/column shapes, field types, scheduling metadata, path names, symlinks/duplicate paths, document presence, sizes and checksums. SQL foreign keys reject broken relationships. Limits: **50 MB compressed**, **100 MB expanded**, **10 MB manifest**, **50,000 rows per table**. Backups are not encrypted; store them privately.

Restore is explicitly **replace**, not merge. Files are written under fresh private names before one database transaction replaces records. If validation, staging or the transaction fails, prior data stays intact and staged files are removed. Old files are collected only after commit; leftover orphan cleanup retries at startup. A process interruption before commit can leave harmless staged orphans, cleaned at next startup. Active focus clocks are not resumed from backups. Export a backup before destructive operations. The app avoids broad storage permissions and uses the Android system picker.

## Testing and known limitations

See `VALIDATION.md` for actual checks and outstanding phone checks. Widget screenshots are Flutter-rendered previews, not physical-device screenshots. Android platform integrations require phone testing: native PDF rendering, system pickers, notification denial/delivery/reboot, online service availability, OEM battery policies and installation. Native phone/emulator checks have not been performed in this environment. Online service responses may change or be unavailable; errors leave offline data usable. External sites may offer optional accounts; StudyForge has none.

The project is Android-only. There is no web build, shared student workspace, cloud sync or automatic backup server. Online search sends the search phrase to Wikipedia; it never uploads private study records. All licensing/permission decisions for imported course documents remain with the person importing them. No official university endorsement is claimed.
