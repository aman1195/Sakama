-- 0006: ai_usage monitoring — operator visibility on AI spend + anon abuse.
--
-- The v1 anon-abuse posture (roadmap 3.5d) is: per-user daily caps + Supabase's
-- per-IP anon-signup rate limit + MONITORING, deferring attestation until abuse
-- actually appears. This view is the monitoring piece: it lets the operator see
-- the farm signal — a spike in DISTINCT users each maxing a feature on one day
-- (PhotoSnap especially, since vision is the pricey call).
--
-- SECURITY: security_invoker = on, so the view runs with the QUERYING role's
-- privileges, never the owner's. service_role (dashboard SQL editor, the
-- operator) bypasses RLS and sees the true cross-user aggregate; a client role
-- that somehow reached it would be constrained by ai_usage's own RLS (own rows
-- only), so there is no cross-user leak. We also revoke client access outright:
-- this is an operator tool, not app data.

create or replace view public.admin_ai_usage_daily
with (security_invoker = on) as
select
  day,
  feature,
  count(distinct user_id) as distinct_users,
  sum(count)              as total_calls,
  max(count)              as max_user_calls,
  round(avg(count), 1)    as avg_user_calls
from public.ai_usage
group by day, feature;

-- Operator-only. No app role may read it.
revoke all on public.admin_ai_usage_daily from anon, authenticated;

comment on view public.admin_ai_usage_daily is
  'Operator monitoring (3.5d). Read in the dashboard SQL editor as service_role. '
  'Abuse signal: distinct_users rising sharply day-over-day for a feature while '
  'max_user_calls sits at the cap = likely anon farming. Per-user drill-down: '
  'select day, feature, user_id, count from public.ai_usage '
  'where day = ''YYYY-MM-DD'' order by count desc;';
