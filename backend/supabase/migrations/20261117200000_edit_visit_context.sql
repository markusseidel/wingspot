-- The reason for an airport visit can be corrected after it was uploaded, like the details of a flight: when the app
-- sends the visit again, the owner's row takes the new visit_context. The function text is patched in place so the long
-- sync function isn't copied again.
do $$
declare
  def text;
  patched text;
begin
  select pg_get_functiondef('public.sync_checkins(jsonb)'::regprocedure) into def;
  patched := replace(def, 'seat = excluded.seat
        where checkins.user_id = uid', 'seat = excluded.seat, visit_context = excluded.visit_context
        where checkins.user_id = uid');
  if patched = def then
    raise exception 'sync_checkins did not have the expected text';
  end if;
  execute patched;
end;
$$;
