-- hardening_a5_profiles_append_only — §A5 of the hardening prompt.
-- Profiles are a time-series; re-fit APPENDS, never overwrites
-- (SCIENCE-SPEC §6). UPDATE statements that change content fields are
-- rejected; only valid_to / updated_at / deleted_at may change — i.e.
-- close out a row; the new state must be inserted as a new row.

create or replace function public._profiles_append_only_guard() returns trigger
language plpgsql set search_path = '' as $$
declare immutable_fields text[] := array['org_id','person_id','source','traits_json','cognitive_json','values_json','derived_json','consent_id','valid_from'];
declare f text;
begin
  foreach f in array immutable_fields loop
    if (to_jsonb(old) -> f) is distinct from (to_jsonb(new) -> f) then
      raise exception 'profiles is append-only: cannot UPDATE column "%" on row %. Use "close old (set valid_to=now()) + insert new" pattern. SCIENCE-SPEC §6.', f, old.id;
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_profiles_append_only on public.profiles;
create trigger trg_profiles_append_only
  before update on public.profiles
  for each row execute function public._profiles_append_only_guard();
