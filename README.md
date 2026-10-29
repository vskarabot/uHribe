# uHribe

A Slovenian mobile app for browsing and logging ascents of Slovenia's
mountains and hills. Flutter + Supabase + Mapbox.

- **Peaks** — searchable list, filterable by mountain range and elevation
  band.
- **Map** — every peak on a Mapbox map (`Outdoors` style), with clustering
  and your own location.
- **Peak** — elevation, coordinates, Wikipedia, hiking routes, and the
  check-in button ("Osvojil sem vrh").
- **Check-in** — a visit is only recorded if you are actually on the summit.
  The app takes a location fix and the server measures the distance (50 m by
  default, adjustable per peak; a poor GPS fix widens the radius, but at most
  to double). Mocked locations are refused.
- **Offline** — peaks and their routes can be downloaded before a hike. With
  no signal a check-in queues on the device and syncs itself once the network
  comes back.
- **Profile** — edit your profile (name, photo, region), browse your visits,
  and see stats: peaks visited, total visits, visits this year, cumulative
  elevation, highest summit, and first and last ascent.
- **Friends** — find other hikers by name, send and accept friend requests,
  and follow your friends' ascents in the Activity feed. Friends see which
  peak and when, never where exactly you stood or your notes.

Peak and route data is imported from OpenStreetMap. Anyone can register with
an email address and password.

The app's interface is in Slovenian.

---

## Getting started

Requires Flutter with Dart SDK **3.11.4** or newer (`flutter --version`).

### 1. Supabase

1. Create a new project at [supabase.com](https://supabase.com).
2. In the **SQL Editor**, run [`supabase/schema.sql`](supabase/schema.sql) —
   the whole schema in one file, safe to run more than once.
3. Under **Authentication → Sign In / Providers**, leave Email enabled and
   "Allow new users to sign up" on. With "Confirm email" on, new users get a
   confirmation link and log in after clicking it — set **Authentication →
   URL Configuration → Site URL** to a page that says so, since the app does
   not handle the link itself.
4. Optionally, under **Authentication → Users → Add user**, create a user by
   hand (email + password, tick "Auto confirm").
5. From **Settings → API**, note the Project URL, the `anon`/`publishable`
   key, and the `service_role` key (the last one is for the import script
   only).

### 2. Mapbox

Create two tokens at [account.mapbox.com](https://account.mapbox.com):

- a **public** one (`pk.…`), used by the app;
- a **secret** one scoped `Downloads:Read` (`sk.…`), which Gradle and
  CocoaPods need to download the Mapbox SDK at build time. It does not belong
  in the repository:

  - **Android** — `~/.gradle/gradle.properties`:
    ```
    MAPBOX_DOWNLOADS_TOKEN=sk.xxxxxxxxxxxxxxxxxxxx
    ```
  - **iOS** — `~/.netrc`:
    ```
    machine api.mapbox.com
    login mapbox
    password sk.xxxxxxxxxxxxxxxxxxxx
    ```

### 3. Import the data

```bash
cd tool
dart pub get
cp .env.example .env     # SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
dart run import_osm.dart
```

Pulls Slovenian peaks (`natural=peak|hill`) and hiking routes
(`route=hiking`) from the Overpass API. Only peaks hikers actually go to are
kept: each OSM peak must match a summit on a reference list
(`tool/lib/reference_peaks.dart`) by name and elevation (±30 m). Other peaks
are removed from the database; visits on a removed peak move to the nearest
kept one within 300 m. Safe to re-run — it refreshes the data rather than
duplicating it.

### 4. Run the app

```bash
cd app
cp .env.example .env     # SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, MAPBOX_ACCESS_TOKEN
flutter pub get
flutter run
```

`.env` is gitignored. Don't skip the `cp`: `.env` is listed under `assets:`
in `app/pubspec.yaml`, so without it the build stops with `No file or
variants found for asset: .env`. For the same reason, changing `.env`
requires a restart — a hot restart won't pick it up.

### Checks

```bash
cd app
flutter analyze
flutter test        # needs app/.env, since it builds the same asset bundle

cd ../tool
dart analyze
```
