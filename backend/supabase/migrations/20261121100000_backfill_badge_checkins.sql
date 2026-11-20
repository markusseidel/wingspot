-- Badges earned before the feed showed them have no check-in to show on. Each one gets the newest check-in the person had
-- when they unlocked it, which is the rule the server uses from now on (see 20261121000000_badges_in_feed.sql).
-- Only the link is filled. Levels, progress, XP and unlock times stay as they are. Rows that already have a check-in are
-- left alone, and so are people with no check-in left.
update public.user_badges ub
set checkin_id = (
  select c.id from public.checkins c
  where c.user_id = ub.user_id and c.created_at <= ub.unlocked_at
  order by c.created_at desc, c.id desc
  limit 1)
where ub.checkin_id is null
  and ub.level > 0
  and ub.unlocked_at is not null;
