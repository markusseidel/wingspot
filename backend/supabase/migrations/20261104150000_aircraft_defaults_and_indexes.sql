-- Registrations are entered by users (concept §10), so a new row must never look verified by accident.
alter table public.aircraft alter column data_status set default 'user_submitted';

-- Foreign keys without an index slow down joins and deletes on the table they point to.
create index aircraft_operator_id_idx on public.aircraft (operator_id);
create index aircraft_type_icao_idx on public.aircraft (type_icao);
create index profiles_home_airport_idx on public.profiles (home_airport);
create index sessions_airport_id_idx on public.sessions (airport_id);
create index sessions_user_id_idx on public.sessions (user_id);
create index spotting_locations_airport_id_idx on public.spotting_locations (airport_id);
create index spotting_locations_created_by_idx on public.spotting_locations (created_by);
create index checkins_destination_id_idx on public.checkins (destination_id);
create index checkins_operator_id_idx on public.checkins (operator_id);
create index checkins_origin_id_idx on public.checkins (origin_id);
create index checkins_session_id_idx on public.checkins (session_id);
create index checkins_spot_location_id_idx on public.checkins (spot_location_id);
create index checkins_type_icao_idx on public.checkins (type_icao);
create index user_badges_badge_id_idx on public.user_badges (badge_id);
create index user_badges_checkin_id_idx on public.user_badges (checkin_id);
create index comments_user_id_idx on public.comments (user_id);
create index reports_reporter_idx on public.reports (reporter);
