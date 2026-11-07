-- Milestone 7b: the people the caller has blocked, with their names.
-- A block hides both people from each other, so the caller can't read the blocked person's profile any more.
-- This lets the app show a list to undo blocks from.
create function public.get_blocks()
returns table (id uuid, username text, display_name text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.username, p.display_name
  from public.blocks b
  join public.profiles p on p.id = b.blocked
  where b.blocker = auth.uid()
  order by p.username;
$$;
revoke execute on function public.get_blocks() from public;
grant execute on function public.get_blocks() to authenticated;
