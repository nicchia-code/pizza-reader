insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'pizza-books',
  'pizza-books',
  false,
  52428800,
  array['application/json', 'application/octet-stream']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'books'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) like '%storage_path%'
      and pg_get_constraintdef(con.oid) like '%.' || 'pb%'
  loop
    execute format('alter table public.books drop constraint %I', constraint_name);
  end loop;
end $$;

alter table public.books
  add constraint books_storage_path_json_check
  check (storage_path like '%.json');

do $$
declare
  policy_name text;
begin
  for policy_name in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'Users can % own pizza%objects'
  loop
    execute format('drop policy if exists %I on storage.objects', policy_name);
  end loop;
end $$;

drop policy if exists "Users can read own reader objects" on storage.objects;
create policy "Users can read own reader objects"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.json'
);

drop policy if exists "Users can insert own reader objects" on storage.objects;
create policy "Users can insert own reader objects"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.json'
);

drop policy if exists "Users can update own reader objects" on storage.objects;
create policy "Users can update own reader objects"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.json'
)
with check (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.json'
);

drop policy if exists "Users can delete own reader objects" on storage.objects;
create policy "Users can delete own reader objects"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.json'
);
