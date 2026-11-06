# Security

## Reporting a problem

Please don't open a public issue for a security problem. Report it privately on GitHub instead: use
**Security → Report a vulnerability** on this repository.

Include what you found, how to reproduce it, and which part is affected (the iOS app, the API, or the database). I'll answer as soon as I can, and I'll say when it is fixed.

## What is in this repository

- The app's Supabase **publishable key** is in `ios/Config/Wingspot.xcconfig` on purpose. It is designed to be public. What protects the data is row-level security in the database, and the tests in `backend/supabase/tests/database` check exactly who can read and write what.
- No secret keys are stored here. Anything secret (the service role key, sign-in provider secrets, the email sending key) lives in the Supabase project settings.

If you find a key, token or password in this repository or its history, please report it as above.
