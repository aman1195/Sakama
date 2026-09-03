-- A7: storage for photos, and the isolation that has to come with it.
--
-- Two buckets, because the two kinds of photo are not the same risk:
--
--   progress-photos — a person's body, taken to track their own change. This
--                     is the most sensitive thing this app will ever hold.
--                     Reached ONLY through short-lived signed URLs.
--   meal-photos     — a plate of food, kept so the gallery can show what was
--                     eaten. Still private, still per-user, but an ordinary
--                     authenticated read is proportionate.
--
-- BOTH ARE PRIVATE. `public = false` on each. "Plain authenticated access" in
-- the design note means "no signed-URL ceremony", NOT "anyone with the link".
-- A public bucket in Supabase serves objects to the open internet with no
-- token at all, which for either of these would be the whole database of a
-- health app sitting on a guessable path.
--
-- THE PATH IS THE SECURITY BOUNDARY. Every object MUST be stored as
--
--     <user_id>/<anything>
--
-- because the policies below authorise on the first path segment. An object
-- written anywhere else is unreachable by its own owner — deliberately. The
-- client builds this path; there is no way to enforce a naming convention in
-- Postgres beyond refusing what does not match, which is what these do.
--
-- Nothing here is on the PowerSync publication. Storage objects are not synced
-- rows; the DEVICE keeps the local file and the row that points at it, and the
-- upload rides the existing offline queue.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('progress-photos', 'progress-photos', false, 10485760,
   array['image/jpeg', 'image/png', 'image/webp']),
  ('meal-photos', 'meal-photos', false, 10485760,
   array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- A size ceiling and a MIME allowlist are not decoration. Without them a
-- bucket is an unmetered file host attached to a free tier, and an upload of
-- text/html served back to a browser is a stored-XSS primitive. 10 MB is
-- generous for a 1200px JPEG at ~85% (typically well under 1 MB) and leaves
-- room for an unresized image from a future camera.

-- storage.objects already has RLS enabled by Supabase. These policies are
-- ADDITIVE, and their shape mirrors every user table in this project:
-- the owner, and nobody else, for each of the four verbs separately.
--
-- `(storage.foldername(name))[1]` is the first path segment. Compared as text
-- against auth.uid()::text because the path is a string, not a uuid.
--
-- WRITTEN OUT LONGHAND, deliberately. The first version generated these in a
-- `do $$ ... format() ... $$` loop over the two bucket names. It failed on the
-- live database: `%L` renders a quoted LITERAL, and `create policy` needs an
-- IDENTIFIER (`%I`). Eight plain statements cannot make that mistake, and a
-- security boundary is the last place to save twenty lines by adding a layer
-- of indirection between what is written and what runs.

create policy "progress-photos: read own" on storage.objects
  for select to authenticated
  using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "progress-photos: write own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "progress-photos: update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "progress-photos: delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "meal-photos: read own" on storage.objects
  for select to authenticated
  using (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "meal-photos: write own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "meal-photos: update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "meal-photos: delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- WHAT THE PATH CHECK ACTUALLY WITHSTANDS (probed against the live project,
-- 2026-09-03, with the owner's own JWT aiming outside their prefix). Every one
-- refused with "new row violates row-level security policy":
--
--   <victim>/x.jpg                 plain write into another user's folder
--   <owner>extra/x.jpg             prefix smear — the segment must match whole
--   <owner>/../<victim>/x.jpg      traversal
--   /<victim>/x.jpg                leading slash
--   rootlevel.jpg                  no folder at all (there is no bucket root)
--
-- and <owner>/ok.jpg wrote, so the check is not simply refusing everything.
--
-- THE MIME ALLOWLIST TRUSTS THE CLIENT'S HEADER, NOT THE BYTES. Measured:
-- declaring `text/html` is refused ("mime type text/html is not supported"),
-- but HTML bytes declared as `image/jpeg` are ACCEPTED. The allowlist still
-- does the job it is here for — the object is served back as the declared,
-- allowlisted type, so a browser will not execute it — but it is not
-- validation. The client must re-encode images it uploads rather than trusting
-- what the picker hands it.
--
-- ANONYMOUS IDENTITIES CAN UPLOAD. Anonymous sign-in is enabled, and an
-- anonymous user IS `authenticated` with a real uid, so these policies admit
-- them. That is intended: auth_service converts anonymous -> email in place
-- with `updateUser`, KEEPING the uid, so photos taken before signup are not
-- orphaned. The residual case is an anonymous identity that is never converted
-- and then lost (reinstall): its objects are unreachable by anyone, including
-- A10's deletion flow, because nobody can authenticate as that uid again. Body
-- photos that no one can delete are a retention problem, not just a storage
-- bill — worth a sweep policy before this ships to users.

-- HOW A DENIAL LOOKS, because it is not what you expect and it decides whether
-- a probe proves anything (measured against the live project, 2026-09-03):
--
--   denied WRITE : HTTP 400, body {"statusCode":"403", ...
--                  "new row violates row-level security policy"}   ← explicit
--   denied READ  : HTTP 400, body {"statusCode":"404", "NoSuchKey",
--                  "Object not found"}                             ← NOT explicit
--
-- Supabase hides existence on a denied read rather than returning 403, which is
-- the right default and makes a read denial INDISTINGUISHABLE from an object
-- that was never there. So "the other user got an error" proves nothing on its
-- own. The proof is the pair: the owner reads 200 on a path, and the other user
-- is told it does not exist. verify-rls.sh does it in that order for that
-- reason. Every storage error is wrapped in HTTP 400 regardless of cause, so
-- assert on the body, never the status code.

-- DELETE IS THE USER'S, and it matters more here than on a row. A photo of
-- someone's body that they cannot remove is worse than one they never took,
-- and A10 (account deletion) has to be able to empty these buckets. Objects
-- are NOT cascaded by `on delete cascade` from auth.users the way table rows
-- are — storage.objects has no FK to the user — so deletion must be explicit
-- in the deletion flow. Written here so the next person finds it before they
-- assume the cascade covers it.
