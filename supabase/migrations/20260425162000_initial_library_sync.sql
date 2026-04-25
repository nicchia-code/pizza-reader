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
  array['application/vnd.pizza-book+json', 'application/json', 'application/octet-stream']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.books (
  id text not null,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  author text,
  source_file_name text,
  storage_bucket text not null default 'pizza-books',
  storage_path text not null,
  byte_length bigint not null check (byte_length >= 0),
  sha256 text check (sha256 is null or sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, id),
  unique (user_id, storage_path),
  check (char_length(id) between 1 and 256),
  check (char_length(title) > 0),
  check (storage_bucket = 'pizza-books'),
  check (starts_with(storage_path, user_id::text || '/')),
  check (storage_path like '%.pb')
);

create table if not exists public.reading_progress (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  book_id text not null,
  paragraph_index integer not null default 0 check (paragraph_index >= 0),
  word_index integer not null default 0 check (word_index >= 0),
  progress_fraction double precision not null default 0
    check (progress_fraction >= 0 and progress_fraction <= 1),
  updated_at timestamptz not null default now(),
  primary key (user_id, book_id),
  foreign key (user_id, book_id)
    references public.books(user_id, id)
    on delete cascade
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_books_updated_at on public.books;
create trigger set_books_updated_at
before update on public.books
for each row execute function public.set_updated_at();

drop trigger if exists set_reading_progress_updated_at on public.reading_progress;
create trigger set_reading_progress_updated_at
before update on public.reading_progress
for each row execute function public.set_updated_at();

alter table public.books enable row level security;
alter table public.reading_progress enable row level security;

drop policy if exists "Users can read own books" on public.books;
create policy "Users can read own books"
on public.books
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "Users can insert own books" on public.books;
create policy "Users can insert own books"
on public.books
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "Users can update own books" on public.books;
create policy "Users can update own books"
on public.books
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users can delete own books" on public.books;
create policy "Users can delete own books"
on public.books
for delete
to authenticated
using (user_id = auth.uid());

drop policy if exists "Users can read own reading progress" on public.reading_progress;
create policy "Users can read own reading progress"
on public.reading_progress
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "Users can insert own reading progress" on public.reading_progress;
create policy "Users can insert own reading progress"
on public.reading_progress
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "Users can update own reading progress" on public.reading_progress;
create policy "Users can update own reading progress"
on public.reading_progress
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users can delete own reading progress" on public.reading_progress;
create policy "Users can delete own reading progress"
on public.reading_progress
for delete
to authenticated
using (user_id = auth.uid());

grant select, insert, update, delete on public.books to authenticated;
grant select, insert, update, delete on public.reading_progress to authenticated;

drop policy if exists "Users can read own pizza book objects" on storage.objects;
create policy "Users can read own pizza book objects"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.pb'
);

drop policy if exists "Users can insert own pizza book objects" on storage.objects;
create policy "Users can insert own pizza book objects"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.pb'
);

drop policy if exists "Users can update own pizza book objects" on storage.objects;
create policy "Users can update own pizza book objects"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.pb'
)
with check (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.pb'
);

drop policy if exists "Users can delete own pizza book objects" on storage.objects;
create policy "Users can delete own pizza book objects"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'pizza-books'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name like '%.pb'
);
