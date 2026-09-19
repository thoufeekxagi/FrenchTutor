# Supabase account cleanup tool

`delete_test_user.dart` is the only supported operator path for permanently
deleting a learner account. It uses the Supabase Auth admin API, the REST API,
and Storage API with the service-role key kept in the shell environment. It
does not call the app, Edge Functions, or a broad SQL delete.

## Local operator setup

The repository ignores `flutter_app/tool/.env`. Keep the production key in that
file only; never commit it, put it in Flutter code, or paste it into chat.

Create `flutter_app/tool/.env` with:

```sh
SUPABASE_URL=https://oxfnrsjskdjbroekxdco.supabase.co
SUPABASE_SERVICE_ROLE_KEY=the-legacy-service-role-key
# Optional newer key kept for backend migration; the current Dart tool uses the line above.
SUPABASE_SECRET_KEY=the-sb-secret-key
```

Then run the exact-email wrapper from `flutter_app/tool`:

```sh
./run_delete_test_user.sh thoufeekbaber1@gmail.com
```

The wrapper requires one exact email, loads the ignored local `.env`, passes the
exact confirmation automatically, and runs the script's existing post-delete
verification. It cannot enumerate or bulk-delete accounts.

## Interactive use

Put only the accounts that are safe to remove in the allowlist. The blank
prompt uses `DELETE_DEFAULT_EMAIL` when that account exists; with one existing
allowlisted account it is also selected by default.

```sh
export SUPABASE_URL="https://YOUR_PROJECT_REF.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<server-only service-role key>"
export DELETE_ALLOWED_EMAILS="first@example.com,second@example.com"
export DELETE_DEFAULT_EMAIL="first@example.com"

# Shows the selected account and row/object counts. It does not delete.
dart run tool/delete_test_user.dart

# Lists only currently existing allowlisted Auth accounts.
dart run tool/delete_test_user.dart --list
```

## Cloud/agent use

Agents must select the exact email explicitly. A dry run is still the default;
`--execute` and an exact confirmation are both required for deletion.

```sh
export DELETE_USER_CONFIRM="first@example.com"
dart run tool/delete_test_user.dart \
  --email="first@example.com" --execute
```

`DELETE_USER_EMAIL=first@example.com` can be used instead of `--email` for a
job runner. If `DELETE_ALLOWED_EMAILS` is set, the selected email must be in
that allowlist. The old `DELETE_TEST_USER_CONFIRM` variable remains accepted
as a compatibility alias.

The tool removes only the selected Auth user, that user's profile and known
learner-owned rows, objects under that user's Storage prefixes, and referral
redemptions for referral codes owned by that user. Shared catalogs are not in
the deletion list. It verifies that Auth, rows, and Storage are empty for the
selected user before reporting success.

Never put `SUPABASE_SERVICE_ROLE_KEY` in Flutter code, app assets, CI logs,
`--dart-define`, or a public agent configuration. Do not remove an account by
omitting `--email` in a non-interactive job.
