# Pizza Reader

Client-side Flutter app for fast reading ebooks.

Pizza Reader converts supported source files in the browser into a universal
Pizza Book `.pb` file, then reads one word at a time with a central pivot
letter and adjustable WPM.

## Current Scope

- Flutter web + Android scaffold.
- Client-side import for `txt`, `md`, `html`, `fb2`, `epub`, and `.pb`.
- `.pb` v1 as canonical UTF-8 JSON with deterministic SHA-256 content hash.
- Reader modes: `auto`, `hold`, `manual`.
- Weighted pacing: punctuation and long words get more time while preserving
  the target average WPM.
- Normal text overlay for jumping back to a line/word.
- Email magic-code auth adapter for Supabase.
- Private Supabase Storage upload/download/delete for `.pb` plus
  library/progress tables.
- Fake auth/library repositories for local development without credentials.

## Run

Without Supabase credentials the app runs with fake local repositories:

```sh
HOME=/tmp XDG_CONFIG_HOME=/tmp DART_SUPPRESS_ANALYTICS=true \
FLUTTER_SUPPRESS_ANALYTICS=true flutter run -d web-server --web-port 8080
```

With Supabase:

```sh
HOME=/tmp XDG_CONFIG_HOME=/tmp DART_SUPPRESS_ANALYTICS=true \
FLUTTER_SUPPRESS_ANALYTICS=true flutter run -d web-server --web-port 8080 \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

For a static build:

```sh
HOME=/tmp XDG_CONFIG_HOME=/tmp DART_SUPPRESS_ANALYTICS=true \
FLUTTER_SUPPRESS_ANALYTICS=true flutter build web
```

## Verify

```sh
HOME=/tmp XDG_CONFIG_HOME=/tmp DART_SUPPRESS_ANALYTICS=true \
FLUTTER_SUPPRESS_ANALYTICS=true flutter analyze

HOME=/tmp XDG_CONFIG_HOME=/tmp DART_SUPPRESS_ANALYTICS=true \
FLUTTER_SUPPRESS_ANALYTICS=true flutter test
```

## Supabase

Apply the SQL migration in `supabase/migrations`, then configure the app with
`SUPABASE_URL` and `SUPABASE_ANON_KEY`.

More details are in `docs/supabase.md`.

## Notes

MOBI/AZW import is intentionally unsupported in the current client-only MVP.
The importer returns a clear `UnsupportedError` instead of silently producing a
bad `.pb`.
