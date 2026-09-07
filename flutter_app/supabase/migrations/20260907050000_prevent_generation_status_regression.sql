-- Real bug found in production data: the client's push-to-server sync
-- (_syncAdaptiveCourseSessionNow in sync_service.dart) writes whatever the
-- device's own local cache currently believes about a session, including
-- resetting generation_status back to 'queued' with a null artifact when
-- the local copy simply has not caught up yet to a 'ready' row the server
-- already finished generating. That push has no "don't downgrade" guard,
-- unlike the reverse (server-to-local) hydration direction, which
-- correctly only accepts a remote row when it is newer. The result: a
-- fully generated, validated lesson could be silently regressed back to
-- queued/no-artifact by the client's own routine sync, discarding real
-- work and making a learner watch a lesson they already reached
-- "generate" all over again -- exactly the flickering ready/generating
-- behavior reported directly from a real device.
--
-- This is enforced here, at the database level, instead of (only) fixing
-- the client, because this is the one place that can protect every
-- current and future write path with a single, atomic, unbypassable rule:
-- once a row is genuinely ready with a real artifact, nothing may reset it
-- to queued/no-artifact except a write that also carries a real reason
-- (a generation_error, or the artifact actually changing). A stale client
-- pushing back a blank "queued" snapshot of a row it has not refreshed
-- yet is never a legitimate transition.
create or replace function public.prevent_generation_status_regression()
returns trigger as $$
begin
  if old.generation_status = 'ready'
     and old.artifact_json is not null
     and new.generation_status = 'queued'
     and new.artifact_json is null
     and new.generation_error is null then
    new.generation_status := old.generation_status;
    new.artifact_kind := old.artifact_kind;
    new.artifact_json := old.artifact_json;
    new.generation_attempts := old.generation_attempts;
    new.generation_error := old.generation_error;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists prevent_generation_status_regression_trigger on public.adaptive_course_sessions;
create trigger prevent_generation_status_regression_trigger
before update on public.adaptive_course_sessions
for each row execute function public.prevent_generation_status_regression();
