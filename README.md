# FreshStart

FreshStart helps people reduce household food waste by tracking pantry ingredients and finding recipes that use them.

## Current milestone

The current milestones include a Haskell-served dashboard, pure expiration-status calculations, recipe suggestions ranked by ingredient matches, and a validated form for adding pantry items. Added items currently live in memory and reset when the server restarts; MongoDB persistence is planned as a later step.

## Run locally

```bash
cabal run
```

Then open <http://localhost:3000>.

The web server is written in Haskell with Scotty. HTML is rendered with Lucid, and the page styles are in `static/style.css`.
