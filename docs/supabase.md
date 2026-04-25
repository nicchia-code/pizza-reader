# Supabase

PizzaReader expects a Supabase project configured through Dart defines:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

For tests, use the fake repositories in `lib/src/supabase` and do not pass real
credentials.

## Schema

Apply the migration in `supabase/migrations` to create:

- private Storage bucket `pizza-books`;
- `public.books` for `.pb` object metadata;
- `public.reading_progress` for the current reading position;
- RLS policies that restrict rows and Storage objects to `auth.uid()`.

Book objects are uploaded under:

```text
<auth.uid()>/<book_id>.pb
```

That path is part of the Storage RLS policy, so clients must be signed in before
uploading with the real `SupabaseLibraryRepository`.

The `.pb` object body is Pizza Book v1 JSON encoded as UTF-8 and uploaded with
content type `application/vnd.pizza-book+json`.

## Auth

`SupabaseAuthRepository` sends email codes with `signInWithOtp` and verifies
them with `verifyOTP(type: OtpType.email)`.
