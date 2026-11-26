-- Minimum age 16 for an account (docs/MINIMUM-AGE-PLAN.md): the agreement to the community rules and the age confirmation move
-- from the phone to the account, so a second phone or a reinstall does not ask again and there is a record of when it was given.
--
-- Rules version 2 is the first one with "I am 16 or older"; agreeing to version 2 or higher records the age confirmation.
-- Both fields are private: no column grant, so other people never read them. The account's owner reads them with get_my_terms,
-- and export_my_data includes them (it returns the whole profile row).

alter table public.profiles
  add column terms_version integer not null default 0 check (terms_version >= 0),
  add column age_confirmed_at timestamptz;

-- Records that the caller agreed to the rules of p_version. The stored version only goes up, and the first age confirmation is
-- kept (a second phone confirming later does not move it). Returns the stored version.
create function public.accept_terms(p_version integer)
returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  stored integer;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_version is null or p_version < 1 or p_version > 1000 then
    raise exception 'invalid version' using errcode = '22023';
  end if;
  update public.profiles
     set terms_version = greatest(terms_version, p_version),
         age_confirmed_at = case when p_version >= 2 then coalesce(age_confirmed_at, now()) else age_confirmed_at end
   where id = uid
  returning terms_version into stored;
  return stored;
end;
$$;
revoke execute on function public.accept_terms(integer) from public, anon;
grant execute on function public.accept_terms(integer) to authenticated;

-- The caller's own rules version and age confirmation. No row when nobody is signed in.
create function public.get_my_terms()
returns table (terms_version integer, age_confirmed_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.terms_version, p.age_confirmed_at from public.profiles p where auth.uid() is not null and p.id = auth.uid();
$$;
revoke execute on function public.get_my_terms() from public, anon;
grant execute on function public.get_my_terms() to authenticated;
