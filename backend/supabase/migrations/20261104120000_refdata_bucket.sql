-- Public bucket for on-device reference database snapshots (backend/refdata-pipeline).
-- Anyone can download by URL. There are no policies on storage.objects, so clients can't list or
-- upload: only the service role can write.
insert into storage.buckets (id, name, public) values ('refdata', 'refdata', true);
