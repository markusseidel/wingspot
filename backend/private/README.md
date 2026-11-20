# Private files

Files here are not committed (see `.gitignore`), because the repository is public.

`hidden_badges.sql` holds the definitions of the hidden badges, so a surprise stays one. Production already has them. A new or reset database gets them with:

```bash
psql "$DATABASE_URL" -f backend/private/hidden_badges.sql
```

The tests don't need the file: they create their own hidden badges inside the test transaction.
