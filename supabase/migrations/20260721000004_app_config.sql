-- 0004: app_config — the min-version gate + feature kill-switches (MOBILE.md).
--
-- DELIBERATELY UNLIKE the per-user tables: this is GLOBAL, PUBLIC-READ config,
-- not user data. So it is NOT keyed by user_id, NOT added to the powersync
-- publication (the client fetches it over plain REST), and its RLS grants
-- read-to-everyone. Writes are console/service_role only (they bypass RLS);
-- there is intentionally no client insert/update/delete policy.
--
-- Rows are simple key/value:
--   ('min_supported_build', '1')  -- lowest build number allowed to run
--   ('flag.photosnap',      'true') -- a feature kill-switch (M3+)

create table public.app_config (
  key   text primary key,
  value text not null
);

alter table public.app_config enable row level security;
alter table public.app_config force row level security;

-- Public read: both anon (pre-sign-in launches still gate) and authenticated.
create policy "app_config: public read"
  on public.app_config for select
  to anon, authenticated
  using (true);

-- Seed a permissive floor so the gate is inert until we deliberately raise it.
insert into public.app_config (key, value) values ('min_supported_build', '1')
  on conflict (key) do nothing;
