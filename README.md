# FreshStart

FreshStart helps people reduce household food waste by tracking pantry ingredients and finding recipes that use them.

## Current milestone

The current milestones include a Haskell-served dashboard, pure expiration-status calculations, recipe suggestions ranked by ingredient matches, a validated pantry form, and MongoDB Atlas persistence. If `MONGODB_URI` is not set, the app runs with sample data in memory for local UI development.

## Run locally

```bash
set -a
source .env
set +a
cabal run
```

Then open <http://localhost:3000>.

Copy `.env.example` to `.env` in the project root and replace its placeholders with the Atlas connection string and your database user's credentials. The `.env` file is ignored by Git. Never commit it or share its contents. The app uses SCRAM-SHA-256 authentication and verifies Atlas TLS certificates against the operating system certificate store. Pantry documents are stored in the `pantry` collection in the database named by the URI, or `freshstart` if the URI does not specify a database. Initial sample items are added only when this collection is empty.

The MongoDB Haskell driver source is vendored under `vendor/mongoDB` and locally patched to verify TLS server certificates. Its upstream Apache-2.0 license is included there.

The web server is written in Haskell with Scotty. HTML is rendered with Lucid, and the page styles are in `static/style.css`.
