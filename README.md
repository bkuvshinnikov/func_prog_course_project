# FreshStart

FreshStart helps people reduce household food waste by tracking pantry ingredients and finding recipes that use them.

## Current milestone

The first milestone is a Haskell-served dashboard with sample pantry items and recipe suggestions. Database persistence and interactive forms will be added in later steps.

## Run locally

```bash
cabal run
```

Then open <http://localhost:3000>.

The web server is written in Haskell with Scotty. HTML is rendered with Lucid, and the page styles are in `static/style.css`.
