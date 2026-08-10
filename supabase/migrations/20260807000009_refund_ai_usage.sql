-- 0009: refund_ai_usage — give back a budget unit the user never actually spent.
--
-- WHY. increment_ai_usage is charge-on-attempt: it increments BEFORE the
-- provider call, which is the safe default for a cost guardrail (0005). The
-- cost of that default showed up in production on 2026-08-07: OpenRouter
-- returned 402 (insufficient credits) on every PhotoSnap request, and each
-- rejected attempt still consumed one of the user's 8 daily photo estimates.
-- Five of eight were burned on requests that never reached a model. A provider
-- outage would silently cost every user their whole day's allowance.
--
-- APPLIES TO ALL FOUR AI FEATURES: photosnap, estimate, vita, plan_gen. The
-- incident was image-only, but the defect is not: any provider outage would
-- drain every cap it touched. plan_gen has the tightest cap, so a user could
-- lose the ability to generate a plan for a whole day to someone else's outage.
--
-- THE RULE, and it is narrow on purpose:
--   refund ONLY when the provider REJECTED the request (non-2xx), because then
--   no tokens were billed to us either.
--   Do NOT refund when the provider answered 2xx and we failed to use the
--   reply — we were charged for those tokens, so the budget should be too.
-- Refunding the second case would let a malformed-response loop consume real
-- money while the user's counter stayed at zero.
--
-- FLOOR AT ZERO. A refund must never mint budget. greatest(count - 1, 0) keeps
-- a double-refund (retry, duplicate delivery) from handing out free calls.
-- Same security_definer + auth.uid() shape as increment_ai_usage, so a client
-- can only ever affect its OWN counter even if it obtained execute rights.

create or replace function public.refund_ai_usage(p_feature text)
returns int
language sql
security definer
set search_path = public
as $$
  update public.ai_usage
     set count = greatest(count - 1, 0)
   where user_id = (select auth.uid())
     and day = to_char(now() at time zone 'utc', 'YYYY-MM-DD')
     and feature = p_feature
  returning count;
$$;

-- Same grants as increment_ai_usage: the Edge Function calls it as the caller.
revoke all on function public.refund_ai_usage(text) from public, anon;
grant execute on function public.refund_ai_usage(text) to authenticated;
