# Devniques Finance

Company finance manager — **offline-first mobile app** for Android + iOS, built with Flutter.

## What it does

- **Dashboard** — this month's income / expense / net, 6-month bar chart, expenses by category
- **Entries** — add / search / filter income & expense records (amount, category, party, date, payment method, receipt photo)
- **Parties** — clients, vendors, employees
- **Reports** — monthly report with **PDF + CSV export**
- **Users & roles (admin)** — promote staff to admin
- **Offline-first** — no internet? Entries save on the phone and sync automatically when back online. Pending count shown in the app.

## Roles (enforced in the database, not just the UI)

| | Add | Edit | Delete | Manage users |
|---|---|---|---|---|
| **Admin** | yes | yes | yes | yes |
| **Staff** | yes | no | no | no |

Every change is written to an `audit_log` (who did what, when) by database triggers.

## Tech

- **App:** Flutter (Dart) — one codebase → Android + iOS
- **Database:** Supabase (PostgreSQL) + Row Level Security
- **Offline:** SQLite on-device (sqflite) + sync queue
- **Auth:** Supabase email/password

## Setup

### 1. Supabase project (5 min, free)

1. Go to https://supabase.com → New project. Save the **project URL** and **anon key** (Project Settings → API).
2. SQL Editor → paste the full contents of `supabase/schema.sql` → Run.
   (Creates tables, roles, security policies, receipt storage, default categories.)
3. Authentication → Providers → Email → **turn OFF "Confirm email"**
   (so staff can sign up and sign in immediately; the app assigns `staff` role by default).

### 2. Make yourself admin

1. Run the app, create your account on the login screen.
2. In Supabase SQL Editor run:
   ```sql
   update public.profiles set role = 'admin' where email = 'you@devniques.com';
   ```
3. Sign out / sign in again in the app.

New staff: they tap "Create staff account" on the login screen → they land as **staff (add-only)** → you promote them in **More → Users & roles**.

### 3. Flutter project

You need the Flutter SDK: https://docs.flutter.dev/get-started/install

```bash
# 1. create the native shells in an empty folder
flutter create --org com.devniques --project-name devniques_finance app_build

# 2. copy this package over it
cp -r devniques-finance/lib app_build/lib
cp devniques-finance/pubspec.yaml app_build/pubspec.yaml

cd app_build
flutter pub get
```

### 4. Run

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

### 5. Build release files

```bash
# Android APK
flutter build apk --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...

# iOS (needs a Mac + Xcode)
flutter build ipa --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

## Project layout

```
lib/
  main.dart                 app entry (Supabase init)
  app.dart                  theme + auth gate + bottom nav
  core/                     config, theme, formatters
  data/
    models.dart             AppUser, Category, Party, Txn
    local/local_db.dart     SQLite: schema, sync queue, kv store
    remote/supa_service.dart Supabase client wrapper
    repos.dart              repositories + offline sync engine + Riverpod providers
  features/
    auth/                   login / register
    dashboard/              home: totals + charts
    transactions/           list + add/edit form
    categories/             admin: manage categories
    parties/                parties (staff can add)
    reports/                monthly report, PDF/CSV export
    users/                  admin: roles
    more/                   menu, sync, logout
supabase/
  schema.sql                full backend: tables, RLS, triggers, seeds
```

## Notes & limits (v1)

- Conflict rule is **last-write-wins** by `updated_at`. Only admins can edit/delete, so conflicts are rare by design.
- Receipt photos upload immediately when online; when offline they're queued and uploaded on the next sync.
- Currency is PKR (`Rs`). Change `fmtMoney` in `lib/core/formatters.dart` for another currency.
- Deleting a category keeps existing entries' labels (they store the name locally).
