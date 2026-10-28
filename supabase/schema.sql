-- uHribe database schema
--
-- The whole schema, in one file. Paste it into the Supabase SQL Editor and
-- run it. Safe to re-run at any time: every statement is idempotent
-- (IF NOT EXISTS / CREATE OR REPLACE / ON CONFLICT / DROP-then-CREATE for
-- policies), and re-running it brings an older database up to date rather
-- than starting over.
--
-- This replaces the earlier 01_schema / 02_checkins / 03_stats split. Those
-- had to be run in order, and re-running an earlier one undid part of a later
-- one — re-running the old 01 restored a permissive write policy on `visits`
-- that 02 had deliberately removed. One file cannot drift against itself.

create extension if not exists postgis;

-- =========================================================
-- profiles: one row per auth user, holds app-specific data
-- =========================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  avatar_url text,
  home_region text,
  location_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'App-facing user data, separate from auth.users.';
comment on column public.profiles.location_enabled is
  'User opted into showing their location on the map, so the app can enable the puck on load instead of prompting every time. The OS permission is still the source of truth.';

-- Keep updated_at current on every update.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Automatically create a profile whenever a user is added in Auth
-- (including via the Supabase dashboard "Add user" flow).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- No revoke/grant pair on the two functions above, unlike every RPC further
-- down: both return `trigger`, so PostgREST will not expose them and a direct
-- call errors out. There is no caller to restrict.

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill profiles for any users that already existed before this ran.
insert into public.profiles (id, email, display_name)
select u.id, u.email, coalesce(u.raw_user_meta_data ->> 'display_name', split_part(u.email, '@', 1))
from auth.users u
on conflict (id) do nothing;

alter table public.profiles enable row level security;

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- =========================================================
-- avatars: storage bucket for profile pictures
-- Files are stored as "<user_id>/avatar.<ext>" so each user can only
-- touch their own object, and are publicly readable for display.
-- =========================================================
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "Avatar images are publicly readable" on storage.objects;
create policy "Avatar images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "Users can upload own avatar" on storage.objects;
create policy "Users can upload own avatar"
  on storage.objects for insert
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users can update own avatar" on storage.objects;
create policy "Users can update own avatar"
  on storage.objects for update
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users can delete own avatar" on storage.objects;
create policy "Users can delete own avatar"
  on storage.objects for delete
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- =========================================================
-- peaks: Slovenian summits, imported from OpenStreetMap
-- =========================================================
create table if not exists public.peaks (
  id bigint primary key, -- OSM node id
  name text not null,
  name_alt text,
  elevation_m integer,
  location geography(Point, 4326) not null,
  lat double precision generated always as (ST_Y(location::geometry)) stored,
  lon double precision generated always as (ST_X(location::geometry)) stored,
  wikipedia text,
  description text,
  -- Null means "use the default". Broad summit plateaus (or peaks whose OSM
  -- node sits off the actual high point) can be widened individually without
  -- loosening the radius for everything.
  checkin_radius_m integer,
  updated_at timestamptz not null default now()
);

-- For databases created before the check-in work landed.
alter table public.peaks
  add column if not exists checkin_radius_m integer;

comment on column public.peaks.checkin_radius_m is
  'Overrides the default check-in radius for this peak, in metres. Null = default.';

create index if not exists peaks_location_idx on public.peaks using gist (location);
create index if not exists peaks_name_idx on public.peaks using gin (to_tsvector('simple', name));

alter table public.peaks enable row level security;

drop policy if exists "Peaks are publicly readable" on public.peaks;
create policy "Peaks are publicly readable"
  on public.peaks for select
  using (true);

-- =========================================================
-- hiking_routes: hiking relations from OpenStreetMap
-- =========================================================
create table if not exists public.hiking_routes (
  id bigint primary key, -- OSM relation id
  name text,
  ref text,
  from_name text,
  to_name text,
  difficulty text, -- from OSM sac_scale
  distance_m integer,
  geom geometry(MultiLineString, 4326) not null,
  updated_at timestamptz not null default now()
);

create index if not exists hiking_routes_geom_idx on public.hiking_routes using gist (geom);
-- Matches the geom::geography cast used by link_peaks_routes' ST_DWithin join,
-- so that join can use an index instead of a full nested-loop distance scan.
create index if not exists hiking_routes_geog_idx on public.hiking_routes using gist ((geom::geography));

alter table public.hiking_routes enable row level security;

drop policy if exists "Routes are publicly readable" on public.hiking_routes;
create policy "Routes are publicly readable"
  on public.hiking_routes for select
  using (true);

-- =========================================================
-- peak_routes: which routes pass near which peak
-- =========================================================
create table if not exists public.peak_routes (
  peak_id bigint not null references public.peaks (id) on delete cascade,
  route_id bigint not null references public.hiking_routes (id) on delete cascade,
  primary key (peak_id, route_id)
);

alter table public.peak_routes enable row level security;

drop policy if exists "Peak routes are publicly readable" on public.peak_routes;
create policy "Peak routes are publicly readable"
  on public.peak_routes for select
  using (true);

drop function if exists public.link_peaks_routes();

-- Links the given peaks to routes that pass within 150m of them. The import
-- calls it in batches, since one call over every peak outlasts the API
-- gateway's request timeout.
create or replace function public.link_peaks_routes(p_peak_ids bigint[])
returns void
language plpgsql
set statement_timeout = '5min'
as $$
begin
  delete from public.peak_routes where peak_id = any(p_peak_ids);

  insert into public.peak_routes (peak_id, route_id)
  select p.id, r.id
  from public.peaks p
  join public.hiking_routes r
    on ST_DWithin(r.geom::geography, p.location, 150)
  where p.id = any(p_peak_ids)
  on conflict do nothing;
end;
$$;

-- =========================================================
-- mountain_areas: Slovenia's 10 "hribovske skupine" (mountain-group)
-- regions, used to classify peaks for filtering in the app. Boundaries are
-- hand-drawn approximations (there's no authoritative boundary dataset for
-- this specific classification) — good enough for filtering, not surveyed.
--
-- The app never reads this table: it carries the same ten names as a Dart
-- constant (Strings.mountainAreas) so the filter works offline. Rename an
-- area here and it has to be renamed there too.
-- =========================================================
create table if not exists public.mountain_areas (
  name text primary key,
  geom geometry(MultiPolygon, 4326) not null
);

create index if not exists mountain_areas_geom_idx on public.mountain_areas using gist (geom);

alter table public.mountain_areas enable row level security;

drop policy if exists "Mountain areas are publicly readable" on public.mountain_areas;
create policy "Mountain areas are publicly readable"
  on public.mountain_areas for select
  using (true);

insert into public.mountain_areas (name, geom) values
  ('Goriško, Notranjsko in Snežniško hribovje',
   ST_GeomFromText('MULTIPOLYGON(((13.35 45.40, 14.55 45.40, 14.55 45.97, 13.35 45.97, 13.35 45.40)))', 4326)),
  ('Julijske Alpe',
   ST_GeomFromText('MULTIPOLYGON(((13.35 46.15, 14.10 46.15, 14.10 46.60, 13.35 46.60, 13.35 46.15)))', 4326)),
  ('Kamniško Savinjske Alpe',
   ST_GeomFromText('MULTIPOLYGON(((14.35 46.15, 15.10 46.15, 15.10 46.42, 14.35 46.42, 14.35 46.15)))', 4326)),
  ('Karavanke',
   ST_GeomFromText('MULTIPOLYGON(((14.10 46.38, 15.05 46.38, 15.05 46.65, 14.10 46.65, 14.10 46.38)))', 4326)),
  ('Pohorje, Dravinjske gorice in Haloze',
   ST_GeomFromText('MULTIPOLYGON(((15.05 45.95, 16.30 45.95, 16.30 46.42, 15.05 46.42, 15.05 45.95)))', 4326)),
  ('Polhograjsko hribovje in Ljubljana',
   ST_GeomFromText('MULTIPOLYGON(((14.15 45.95, 14.65 45.95, 14.65 46.15, 14.15 46.15, 14.15 45.95)))', 4326)),
  ('Posavsko hribovje in Dolenjska',
   ST_GeomFromText('MULTIPOLYGON(((14.55 45.40, 15.60 45.40, 15.60 46.10, 14.55 46.10, 14.55 45.40)))', 4326)),
  ('Prekmurje',
   ST_GeomFromText('MULTIPOLYGON(((15.85 46.35, 16.65 46.35, 16.65 46.88, 15.85 46.88, 15.85 46.35)))', 4326)),
  ('Škofjeloško, Cerkljansko hribovje in Jelovica',
   ST_GeomFromText('MULTIPOLYGON(((13.85 45.95, 14.45 45.95, 14.45 46.25, 13.85 46.25, 13.85 45.95)))', 4326)),
  ('Strojna, Košenjak, Kozjak in Slovenske gorice',
   ST_GeomFromText('MULTIPOLYGON(((14.95 46.42, 15.90 46.42, 15.90 46.88, 14.95 46.88, 14.95 46.42)))', 4326))
on conflict (name) do update set geom = excluded.geom;

-- Added after mountain_areas exists, because the FK points at it.
alter table public.peaks add column if not exists mountain_area text references public.mountain_areas (name);

-- Classifies every peak into the mountain_area whose (approximate) boundary
-- contains it, falling back to the nearest area for the handful of peaks
-- that land in a gap between the hand-drawn polygons (e.g. near a coastline
-- or a seam between two areas). Re-run after every import.
create or replace function public.classify_peak_mountain_areas()
returns void
language plpgsql
set statement_timeout = '5min'
as $$
begin
  analyze public.peaks;
  analyze public.mountain_areas;

  update public.peaks p
  set mountain_area = (
    select a.name
    from public.mountain_areas a
    where ST_Contains(a.geom, p.location::geometry)
    order by ST_Area(a.geom) asc
    limit 1
  );

  update public.peaks p
  set mountain_area = (
    select a.name
    from public.mountain_areas a
    order by a.geom <-> p.location::geometry
    limit 1
  )
  where p.mountain_area is null;
end;
$$;

-- =========================================================
-- visits: a user's log of peaks they've climbed
-- =========================================================
-- A visit is created one way only: the user was physically at the peak and
-- checked in. The distance is measured on the server, never on the device —
-- insert and update are revoked below, so the only way in is check_in_peak().
-- That is what stops an app from simply POSTing a summit it never reached.
--
-- There is no "verified" flag, because there is nothing to flag: a row
-- existing means the server measured it and accepted it.
create table if not exists public.visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade default auth.uid(),
  peak_id bigint not null references public.peaks (id) on delete cascade,
  route_id bigint references public.hiking_routes (id) on delete set null,
  visited_on date not null default current_date,
  notes text,
  lat double precision,
  lon double precision,
  accuracy_m double precision,
  distance_m double precision,
  device_time timestamptz,
  client_id uuid,
  synced_at timestamptz,
  created_at timestamptz not null default now()
);

-- For databases created before the check-in work landed.
alter table public.visits
  add column if not exists lat double precision,
  add column if not exists lon double precision,
  add column if not exists accuracy_m double precision,
  add column if not exists distance_m double precision,
  add column if not exists device_time timestamptz,
  add column if not exists client_id uuid,
  add column if not exists synced_at timestamptz;

comment on column public.visits.device_time is
  'The OS location timestamp of the fix, which for an offline check-in can be
   hours before synced_at. Kept for plausibility checks.';
comment on column public.visits.client_id is
  'Generated on the device when the check-in is queued, so replaying a queued
   check-in after a network timeout cannot create a duplicate.';

create index if not exists visits_user_idx on public.visits (user_id);
create index if not exists visits_peak_idx on public.visits (peak_id);

-- Idempotency for the offline queue: the device generates client_id once, so
-- a retried sync of the same queued check-in lands on this index instead of
-- inserting a second row. check_in_peak()'s replay path depends on it.
create unique index if not exists visits_user_client_idx
  on public.visits (user_id, client_id)
  where client_id is not null;

alter table public.visits enable row level security;

-- Read and delete your own; never insert or update directly.
drop policy if exists "Users read own visits" on public.visits;
create policy "Users read own visits"
  on public.visits for select
  using (auth.uid() = user_id);

drop policy if exists "Users delete own visits" on public.visits;
create policy "Users delete own visits"
  on public.visits for delete
  using (auth.uid() = user_id);

-- Supabase grants the API roles full table access by default, and a select +
-- delete policy pair says nothing about insert — without this revoke a client
-- could still write a summit it never reached.
revoke insert, update on public.visits from anon, authenticated;

-- =========================================================
-- Bulk upsert RPCs used only by the import tool (tool/import_osm.dart).
-- Restricted to service_role so the anon/authenticated clients used by the
-- app can never write peaks/routes, only read them.
-- =========================================================

create or replace function public.upsert_peaks(p_rows jsonb)
returns void
language sql
set statement_timeout = '5min'
as $$
  insert into public.peaks (id, name, name_alt, elevation_m, location, wikipedia, description, updated_at)
  select
    (r ->> 'id')::bigint,
    r ->> 'name',
    r ->> 'name_alt',
    nullif(r ->> 'elevation_m', '')::integer,
    ST_SetSRID(ST_MakePoint((r ->> 'lon')::double precision, (r ->> 'lat')::double precision), 4326)::geography,
    r ->> 'wikipedia',
    r ->> 'description',
    now()
  from jsonb_array_elements(p_rows) as r
  on conflict (id) do update set
    name = excluded.name,
    name_alt = excluded.name_alt,
    elevation_m = excluded.elevation_m,
    location = excluded.location,
    wikipedia = excluded.wikipedia,
    description = excluded.description,
    updated_at = now();
$$;

revoke all on function public.upsert_peaks(jsonb) from public;
grant execute on function public.upsert_peaks(jsonb) to service_role;

create or replace function public.upsert_hiking_routes(p_rows jsonb)
returns void
language sql
set statement_timeout = '5min'
as $$
  insert into public.hiking_routes (id, name, ref, from_name, to_name, difficulty, distance_m, geom, updated_at)
  select
    (r ->> 'id')::bigint,
    r ->> 'name',
    r ->> 'ref',
    r ->> 'from_name',
    r ->> 'to_name',
    r ->> 'difficulty',
    nullif(r ->> 'distance_m', '')::integer,
    ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(r ->> 'geojson'), 4326)),
    now()
  from jsonb_array_elements(p_rows) as r
  on conflict (id) do update set
    name = excluded.name,
    ref = excluded.ref,
    from_name = excluded.from_name,
    to_name = excluded.to_name,
    difficulty = excluded.difficulty,
    distance_m = excluded.distance_m,
    geom = excluded.geom,
    updated_at = now();
$$;

revoke all on function public.upsert_hiking_routes(jsonb) from public;
grant execute on function public.upsert_hiking_routes(jsonb) to service_role;

revoke all on function public.link_peaks_routes(bigint[]) from public;
grant execute on function public.link_peaks_routes(bigint[]) to service_role;

revoke all on function public.classify_peak_mountain_areas() from public;
grant execute on function public.classify_peak_mountain_areas() to service_role;

drop function if exists public.prune_peaks(bigint[]);

-- The two prune steps below never remove a peak someone has visited, since
-- deleting a peak cascades to its visits.

-- Removes peaks the import no longer returns (not notable), before linking.
create or replace function public.prune_unlisted_peaks(p_keep_ids bigint[])
returns integer
language plpgsql
set statement_timeout = '5min'
as $$
declare
  v_removed integer;
begin
  delete from public.peaks p
  where not (p.id = any(p_keep_ids))
    and not exists (select 1 from public.visits v where v.peak_id = p.id);
  get diagnostics v_removed = row_count;

  -- Fresh planner stats so the batched linking uses the geo indexes.
  analyze public.peaks;
  analyze public.hiking_routes;
  return v_removed;
end;
$$;

revoke all on function public.prune_unlisted_peaks(bigint[]) from public;
grant execute on function public.prune_unlisted_peaks(bigint[]) to service_role;

-- Removes peaks no marked hiking route passes, after linking.
create or replace function public.prune_trailless_peaks()
returns integer
language plpgsql
set statement_timeout = '5min'
as $$
declare
  v_removed integer;
begin
  delete from public.peaks p
  where not exists (select 1 from public.peak_routes pr where pr.peak_id = p.id)
    and not exists (select 1 from public.visits v where v.peak_id = p.id);
  get diagnostics v_removed = row_count;
  return v_removed;
end;
$$;

revoke all on function public.prune_trailless_peaks() from public;
grant execute on function public.prune_trailless_peaks() to service_role;

-- =========================================================
-- RPCs used by the app
-- =========================================================

-- Routes near a given peak, with geometry as GeoJSON for the map.
create or replace function public.routes_for_peak(p_peak_id bigint)
returns table (
  id bigint,
  name text,
  ref text,
  from_name text,
  to_name text,
  difficulty text,
  distance_m integer,
  geojson text
)
language sql
stable
as $$
  select r.id, r.name, r.ref, r.from_name, r.to_name, r.difficulty, r.distance_m,
         ST_AsGeoJSON(r.geom) as geojson
  from public.hiking_routes r
  join public.peak_routes pr on pr.route_id = r.id
  where pr.peak_id = p_peak_id;
$$;

revoke all on function public.routes_for_peak(bigint) from public;
grant execute on function public.routes_for_peak(bigint) to authenticated, anon;

-- Everything the device needs to check in without a network. Downloaded
-- before the hike and cached on the device. Includes the radius so the app
-- can tell the user "you're 120 m away" on the summit itself; the server
-- still re-checks the distance at sync time, so a tampered local copy buys
-- nothing.
create or replace function public.peaks_for_offline(p_peak_ids bigint[])
returns table (
  id bigint,
  name text,
  name_alt text,
  elevation_m integer,
  lat double precision,
  lon double precision,
  wikipedia text,
  description text,
  mountain_area text,
  checkin_radius_m integer
)
language sql
stable
as $$
  select p.id, p.name, p.name_alt, p.elevation_m, p.lat, p.lon,
         p.wikipedia, p.description, p.mountain_area,
         coalesce(p.checkin_radius_m, 50)
  from public.peaks p
  where p.id = any(p_peak_ids);
$$;

revoke all on function public.peaks_for_offline(bigint[]) from public;
grant execute on function public.peaks_for_offline(bigint[]) to authenticated, anon;

-- ---------------------------------------------------------
-- check_in_peak: the only way a visit is ever created
-- ---------------------------------------------------------
-- Mock-location detection is deliberately NOT here. The signal comes from the
-- device and nowhere else — the database has no independent way to tell a
-- synthetic fix from a real one — so a check here could only ever repeat what
-- the device already told us. The app refuses a mocked fix before queueing,
-- which is both the only place it can be checked and the place where the user
-- finds out in time to do something about it.
create or replace function public.check_in_peak(
  p_peak_id bigint,
  p_lat double precision,
  p_lon double precision,
  p_accuracy_m double precision default null,
  p_device_time timestamptz default null,
  p_visited_on date default null,
  p_notes text default null,
  p_route_id bigint default null,
  p_client_id uuid default null
)
returns public.visits
language plpgsql
security definer set search_path = public
as $$
declare
  -- Default radius around the summit node. Generous enough for a GPS fix
  -- under tree cover, tight enough that it means "on the top".
  c_default_radius_m constant double precision := 50;

  v_user_id uuid := auth.uid();
  v_peak public.peaks;
  v_point geography;
  v_distance_m double precision;
  v_radius_m double precision;
  v_allowed_m double precision;
  v_visit public.visits;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = 'UH003';
  end if;

  -- Replay of an already-synced queued check-in: hand back the original row
  -- rather than inserting a duplicate or failing the sync.
  if p_client_id is not null then
    select * into v_visit
    from public.visits
    where user_id = v_user_id and client_id = p_client_id;
    if found then
      return v_visit;
    end if;
  end if;

  select * into v_peak from public.peaks where id = p_peak_id;
  if not found then
    raise exception 'Unknown peak %', p_peak_id using errcode = 'UH002';
  end if;

  v_point := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;
  v_distance_m := ST_Distance(v_peak.location, v_point);
  v_radius_m := coalesce(v_peak.checkin_radius_m, c_default_radius_m);

  -- A poor fix widens the radius, but only up to double it. Without the cap a
  -- client could claim a 10 km accuracy and check in from the valley; without
  -- any allowance an honest hiker with a ±60 m fix on the summit gets refused.
  v_allowed_m := v_radius_m + least(coalesce(p_accuracy_m, 0), v_radius_m);

  if v_distance_m > v_allowed_m then
    raise exception 'Too far from peak: % m (allowed % m)',
      round(v_distance_m)::int, round(v_allowed_m)::int
      using errcode = 'UH001';
  end if;

  insert into public.visits (
    user_id, peak_id, route_id, visited_on, notes,
    lat, lon, accuracy_m, distance_m,
    device_time, client_id, synced_at
  )
  values (
    v_user_id, p_peak_id, p_route_id,
    coalesce(p_visited_on, current_date),
    nullif(btrim(coalesce(p_notes, '')), ''),
    p_lat, p_lon, p_accuracy_m, v_distance_m,
    p_device_time, p_client_id, now()
  )
  returning * into v_visit;

  return v_visit;
end;
$$;

-- security definer is what makes this work at all: the revoke above means
-- `authenticated` cannot insert into visits, so the function has to carry its
-- owner's rights to do it on their behalf.
revoke all on function public.check_in_peak(
  bigint, double precision, double precision, double precision,
  timestamptz, date, text, bigint, uuid) from public;
grant execute on function public.check_in_peak(
  bigint, double precision, double precision, double precision,
  timestamptz, date, text, bigint, uuid) to authenticated;

-- Logging an ascent made before the app existed, or without it, is left out
-- on purpose for now — there is no self-reported path, so every row in
-- visits was measured against the summit. If that changes, it wants its own
-- function rather than opening up insert on the table.

-- ---------------------------------------------------------
-- my_stats: the profile summary
-- ---------------------------------------------------------
-- Postgres will not replace a function's return type in place, and this one
-- grew over time, so any older signature goes first.
drop function if exists public.my_stats();

create or replace function public.my_stats()
returns table (
  peaks_visited bigint,
  total_visits bigint,
  visits_this_year bigint,
  total_elevation_m bigint,
  highest_peak_name text,
  highest_peak_elevation_m integer,
  first_visit_on date,
  first_visit_peak_name text,
  last_visit_on date,
  last_visit_peak_name text
)
language sql
stable
security definer set search_path = public
as $$
  with mine as (
    select v.id, v.peak_id, v.visited_on, p.name, p.elevation_m
    from public.visits v
    join public.peaks p on p.id = v.peak_id
    where v.user_id = auth.uid()
  ),
  -- Summit height only counts once per peak: climbing Triglav four times is
  -- four visits, but it is not four times its height.
  distinct_peaks as (
    select distinct on (peak_id) peak_id, elevation_m
    from mine
    order by peak_id
  ),
  highest as (
    select name, elevation_m from mine
    order by elevation_m desc nulls last limit 1
  ),
  -- visited_on alone ties whenever two peaks share a day, so id breaks the
  -- tie and keeps "first" and "last" stable between calls.
  first_one as (
    select visited_on, name from mine order by visited_on asc, id asc limit 1
  ),
  last_one as (
    select visited_on, name from mine order by visited_on desc, id desc limit 1
  )
  select
    (select count(distinct peak_id) from mine),
    (select count(*) from mine),
    (select count(*) from mine
       where visited_on >= date_trunc('year', current_date)::date),
    (select coalesce(sum(elevation_m), 0)::bigint from distinct_peaks),
    (select name from highest),
    (select elevation_m from highest),
    (select visited_on from first_one),
    (select name from first_one),
    (select visited_on from last_one),
    (select name from last_one);
$$;

comment on function public.my_stats() is
  'Profile summary for the calling user, derived entirely from their visits.';

-- security definer, so it reads visits past RLS — the body's
-- `where v.user_id = auth.uid()` is what holds it to the caller's own rows.
-- anon would get zero rows anyway, but there is no reason to let it ask.
revoke all on function public.my_stats() from public;
grant execute on function public.my_stats() to authenticated;

-- =========================================================
-- friendships: mutual friends
-- =========================================================
-- One row per pair, whichever side asked first. Accepting flips status to
-- 'accepted'; declining, cancelling and unfriending all delete the row.
create table if not exists public.friendships (
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);

-- Without this, A→B and B→A could both exist as separate pending requests.
create unique index if not exists friendships_pair_idx
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index if not exists friendships_addressee_idx on public.friendships (addressee_id);

alter table public.friendships enable row level security;

drop policy if exists "Users read own friendships" on public.friendships;
create policy "Users read own friendships"
  on public.friendships for select
  using (auth.uid() in (requester_id, addressee_id));

revoke insert, update, delete on public.friendships from anon, authenticated;

create or replace function public.send_friend_request(p_user_id uuid)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.friendships;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = 'UH003';
  end if;
  if p_user_id = v_me then
    raise exception 'Cannot befriend yourself' using errcode = 'UH010';
  end if;

  select * into v_row from public.friendships
  where (requester_id = v_me and addressee_id = p_user_id)
     or (requester_id = p_user_id and addressee_id = v_me);

  if found then
    -- They already asked us: sending back is the same as accepting.
    if v_row.status = 'pending' and v_row.requester_id = p_user_id then
      update public.friendships set status = 'accepted', responded_at = now()
      where requester_id = p_user_id and addressee_id = v_me;
      return 'friends';
    end if;
    return case when v_row.status = 'accepted' then 'friends' else 'outgoing' end;
  end if;

  insert into public.friendships (requester_id, addressee_id) values (v_me, p_user_id);
  return 'outgoing';
end;
$$;

create or replace function public.accept_friend_request(p_user_id uuid)
returns void
language sql
security definer set search_path = public
as $$
  update public.friendships set status = 'accepted', responded_at = now()
  where requester_id = p_user_id and addressee_id = auth.uid() and status = 'pending';
$$;

-- Decline, cancel and unfriend in one: whichever row links the two goes.
create or replace function public.remove_friendship(p_user_id uuid)
returns void
language sql
security definer set search_path = public
as $$
  delete from public.friendships
  where (requester_id = auth.uid() and addressee_id = p_user_id)
     or (requester_id = p_user_id and addressee_id = auth.uid());
$$;

-- Status of every friendship row the caller is part of, from their side.
create or replace function public.my_friends()
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  home_region text,
  status text,
  created_at timestamptz
)
language sql
stable
security definer set search_path = public
as $$
  select p.id, p.display_name, p.avatar_url, p.home_region,
         case
           when f.status = 'accepted' then 'friends'
           when f.requester_id = auth.uid() then 'outgoing'
           else 'incoming'
         end,
         f.created_at
  from public.friendships f
  join public.profiles p
    on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
  where auth.uid() in (f.requester_id, f.addressee_id)
  order by p.display_name;
$$;

-- profiles is only readable by its owner, so finding other people goes
-- through here. Email is deliberately not returned.
create or replace function public.search_profiles(p_query text)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  home_region text,
  status text
)
language sql
stable
security definer set search_path = public
as $$
  select p.id, p.display_name, p.avatar_url, p.home_region,
         case
           when f.status = 'accepted' then 'friends'
           when f.requester_id = auth.uid() then 'outgoing'
           when f.addressee_id = auth.uid() then 'incoming'
           else 'none'
         end
  from public.profiles p
  left join public.friendships f
    on (f.requester_id = auth.uid() and f.addressee_id = p.id)
    or (f.requester_id = p.id and f.addressee_id = auth.uid())
  where auth.uid() is not null
    and p.id <> auth.uid()
    and length(btrim(p_query)) >= 2
    and strpos(lower(p.display_name), lower(btrim(p_query))) > 0
  order by p.display_name
  limit 20;
$$;

-- Friends' ascents, newest climb first. Leaves out where exactly they stood
-- and their notes.
create or replace function public.friends_feed(p_limit integer default 50)
returns table (
  visit_id uuid,
  user_id uuid,
  display_name text,
  avatar_url text,
  peak_id bigint,
  peak_name text,
  elevation_m integer,
  visited_on date,
  created_at timestamptz
)
language sql
stable
security definer set search_path = public
as $$
  with friends as (
    select case when requester_id = auth.uid() then addressee_id else requester_id end as id
    from public.friendships
    where status = 'accepted' and auth.uid() in (requester_id, addressee_id)
  )
  select v.id, v.user_id, pr.display_name, pr.avatar_url,
         v.peak_id, pk.name, pk.elevation_m, v.visited_on, v.created_at
  from public.visits v
  join friends fr on fr.id = v.user_id
  join public.profiles pr on pr.id = v.user_id
  join public.peaks pk on pk.id = v.peak_id
  order by v.visited_on desc, v.created_at desc
  limit least(greatest(p_limit, 1), 200);
$$;

revoke all on function public.send_friend_request(uuid) from public;
grant execute on function public.send_friend_request(uuid) to authenticated;
revoke all on function public.accept_friend_request(uuid) from public;
grant execute on function public.accept_friend_request(uuid) to authenticated;
revoke all on function public.remove_friendship(uuid) from public;
grant execute on function public.remove_friendship(uuid) to authenticated;
revoke all on function public.my_friends() from public;
grant execute on function public.my_friends() to authenticated;
revoke all on function public.search_profiles(text) from public;
grant execute on function public.search_profiles(text) to authenticated;
revoke all on function public.friends_feed(integer) from public;
grant execute on function public.friends_feed(integer) to authenticated;
