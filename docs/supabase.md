# Supabase

PizzaReader expects a Supabase project configured through Dart defines:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

`SUPABASE_ANON_KEY` is also accepted for older projects that still use anon key
terminology.

For tests, use the fake repositories in `lib/src/supabase` and do not pass real
credentials.

## Schema

Apply the migration in `supabase/migrations` to create:

- private Storage bucket `pizza-books`;
- `public.books` for imported ebook metadata;
- `public.reading_progress` for the current reader state:
  `chapter_index`, `word_index`, `wpm`, `mode`, and `progress_fraction`;
- RLS policies that restrict rows and Storage objects to `auth.uid()`.

Book objects are uploaded under:

```text
<auth.uid()>/<book_id>.json
```

That path is part of the Storage RLS policy, so clients must be signed in before
uploading with the real `SupabaseLibraryRepository`.

The stored object body is normalized reader JSON encoded as UTF-8 and uploaded
with content type `application/json`.

`SupabaseLibraryRepository` supports the full book lifecycle:

- `uploadBook` stores normalized reader JSON in Storage and upserts metadata in
  `public.books`;
- `downloadBookBytes` downloads the stored reader object for a listed
  `LibraryBook`;
- `upsertReadingProgress` stores reader progress using chapter and word
  indices, optional `wpm`, optional `mode`, and a normalized fraction;
- `deleteBook` removes the metadata row and stored object. The
  `reading_progress` row is removed by the `books` foreign key cascade.

## Auth

`SupabaseAuthRepository` sends email codes with `signInWithOtp` and verifies
them with `verifyOTP(type: OtpType.email)`.
