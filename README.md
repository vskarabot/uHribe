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

Peak and route data is imported from OpenStreetMap. There is no sign-up —
create user accounts by hand in the Supabase dashboard.

The app's interface is in Slovenian.

---

## Getting started

Requires Flutter with Dart SDK **3.11.4** or newer (`flutter --version`).

### 1. Supabase

1. Create a new project at [supabase.com](https://supabase.com).
2. In the **SQL Editor**, run [`supabase/schema.sql`](supabase/schema.sql) —
   the whole schema in one file, safe to run more than once.
3. Under **Authentication → Sign In / Providers**, leave Email enabled but
   turn off "Allow new users to sign up".
4. Under **Authentication → Users → Add user**, create a user (email +
   password, tick "Auto confirm").
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
kept: a peak needs a Wikipedia/Wikidata link or a summit register
(`summit:register=yes`), and a marked hiking route within 150 m. Peaks that
fail either test are removed from the database, unless someone has already
checked in on them. Safe to re-run — it refreshes the data rather than
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
