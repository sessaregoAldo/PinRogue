# Web hosting (GitHub Pages) + global high scores (Supabase)

The browser build lives in `docs/` and is served by GitHub Pages. High scores go to a
free Supabase database. Until Supabase is configured, the game keeps scores per browser.

## 1. Create the score database (Supabase, ~5 min)

1. Sign up at https://supabase.com and create a **New project** (free tier is fine).
2. Open **SQL Editor → New query**, paste the contents of `supabase/schema.sql`, click **Run**.
   This creates the `scores` table: names of 2–5 letters A–Z, and rules so that
   anyone can read and add scores but nobody can edit or delete them.
3. Open **Project Settings → API** (or **Connect**) and copy:
   - the **Project URL**, like `https://abcdefghijklmnop.supabase.co`
   - the **public** key: the *publishable* key (`sb_publishable_...`) or the legacy *anon* key.
     **Never** use the `service_role` / secret key, because this file ships inside the game.
4. Put them in `leaderboard_config.cfg`:
   ```ini
   [supabase]
   url="https://abcdefghijklmnop.supabase.co"
   key="sb_publishable_xxxxxxxxxxxx"
   table="scores"
   ```
5. Re-export (step 2). Press F5 in Godot to try it locally too. The end screen should say "Saved!"
   without "(this device only)".

To remove junk entries, open **Table Editor → scores** in Supabase and delete them.

## 2. Export the browser build

```bash
tools/export_web.sh            # writes docs/index.html, index.wasm, index.pck, ...
```
It uses the single-threaded web template, so no special server headers are needed.
Re-run it after every change you want to publish.

Optional: preview it locally with `py -m http.server 8080 -d docs` and open http://localhost:8080.

## 3. Publish on GitHub Pages

One-time setup:
1. Create an empty repository on GitHub (e.g. `pinball`).
2. In this folder:
   ```bash
   git init -b main
   git add .
   git commit -m "Pinball game"
   git remote add origin https://github.com/<you>/pinball.git
   git push -u origin main
   ```
3. On GitHub, open the repo: **Settings → Pages → Build and deployment → Source: Deploy from a branch**,
   then pick **Branch: `main`**, folder **`/docs`**, and **Save**.
4. After a minute the game is live at `https://<you>.github.io/pinball/`.

To update the game: run `tools/export_web.sh`, then commit and push.

## Notes
- The public key is meant to be public. The database rules (row level security) are what
  protect the table. Like any client-side game, a determined player could post a fake
  score. If that matters later, move submissions behind a server function that validates them.
- The game remembers each player's last name on their device and offers it again.
- If the online board can't be reached, the score is saved on the player's device and the
  board shows that device's scores, with a message.
