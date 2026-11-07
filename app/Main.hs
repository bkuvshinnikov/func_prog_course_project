{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (bracket)
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import qualified Data.Text as Text
import FreshStart.Domain
import FreshStart.MongoStore
import Lucid
import Network.HTTP.Types.Status (status400)
import Web.Scotty (file, formParam, get, html, post, redirect, scotty, setHeader, status)

samplePantryItems :: [PantryItem]
samplePantryItems =
  [ PantryItem "🥑" "Avocado" "2 pieces" 0
  , PantryItem "🥬" "Baby spinach" "120 g" 1
  , PantryItem "🍅" "Cherry tomatoes" "1 cup" 3
  , PantryItem "🥛" "Greek yogurt" "350 g" 5
  ]

recipes :: [Recipe]
recipes =
  [ Recipe "Creamy avocado toast" "Uses your avocado" "15 min" ["Avocado", "Bread", "Lemon"] "mint"
  , Recipe "Green garden omelette" "Spinach + pantry staples" "20 min" ["Baby spinach", "Eggs", "Feta"] "lavender"
  , Recipe "Tomato yogurt bowl" "Cherry tomatoes + yogurt" "10 min" ["Cherry tomatoes", "Greek yogurt"] "peach"
  ]

main :: IO ()
main = bracket (openPantryStore samplePantryItems) closePantryStore $ \pantryStore ->
  scotty 3000 $ do
    get "/" $ do
      currentPantry <- liftIO (readPantryItems pantryStore)
      html (renderText (homePage currentPantry Nothing))
    post "/pantry" $ do
      name <- formParam "name"
      amount <- formParam "amount"
      daysLeft <- formParam "daysLeft"
      case validatePantryItem name amount daysLeft of
        Left message -> do
          currentPantry <- liftIO (readPantryItems pantryStore)
          status status400
          html (renderText (homePage currentPantry (Just message)))
        Right item -> do
          liftIO (addPantryItem pantryStore item)
          redirect "/"
    get "/style.css" $ do
      setHeader "Content-Type" "text/css; charset=utf-8"
      file "static/style.css"

homePage :: [PantryItem] -> Maybe Text -> Html ()
homePage pantryItems formError = do
  doctype_
  html_ [lang_ "en"] $ do
    head_ $ do
      meta_ [charset_ "utf-8"]
      meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
      title_ "FreshStart — Use what you have"
      link_ [rel_ "stylesheet", href_ "/style.css"]
    body_ $ do
      header_ [class_ "topbar"] $ do
        a_ [class_ "brand", href_ "#top"] $ do
          span_ [class_ "brand-mark"] "f"
          span_ "freshstart"
        nav_ [class_ "main-nav"] $ do
          a_ [class_ "nav-link active", href_ "#pantry"] "My pantry"
          a_ [class_ "nav-link", href_ "#recipes"] "Recipes"
          a_ [class_ "nav-link", href_ "#impact"] "Your impact"
        a_ [class_ "profile", href_ "#profile", title_ "Profile"] "B"

      main_ [id_ "top", class_ "page-wrap"] $ do
        section_ [class_ "hero"] $ do
          div_ [class_ "hero-copy"] $ do
            p_ [class_ "eyebrow"] "A LITTLE LESS WASTE, A LOT MORE TASTE"
            h1_ "Make the most of what’s already in your kitchen."
            p_ [class_ "hero-description"]
              "Keep an eye on your ingredients and find something lovely to make with them."
            a_ [class_ "hero-button", href_ "#recipes"] $ do
              "Find a recipe "
              span_ "↗"
          div_ [class_ "hero-art"] $ do
            div_ [class_ "sun"] mempty
            div_ [class_ "plate"] mempty
            div_ [class_ "leaf leaf-one"] "✳"
            div_ [class_ "leaf leaf-two"] "✳"
            div_ [class_ "art-caption"] "Good food deserves another chance."

        section_ [class_ "welcome-row"] $ do
          div_ $ do
            p_ [class_ "eyebrow dark-eyebrow"] "YOUR KITCHEN, AT A GLANCE"
            h2_ "Good morning, Boris"
          p_ [class_ "date-label"] "Saturday, November 7"

        section_ [class_ "stats-grid", id_ "impact"] $ do
          article_ [class_ "stat-card"] $ do
            div_ [class_ "stat-icon green-icon"] "⌂"
            p_ [class_ "stat-label"] "In your pantry"
            p_ [class_ "stat-value"] (toHtml (Text.pack (show (length pantryItems))))
            p_ [class_ "stat-note"] "ingredients to explore"
          article_ [class_ "stat-card"] $ do
            div_ [class_ "stat-icon peach-icon"] "◷"
            p_ [class_ "stat-label"] "Use soon"
            p_ [class_ "stat-value"] $
              toHtml (Text.pack (show (countItemsNeedingAttention (map itemDaysLeft pantryItems))))
            p_ [class_ "stat-note"] "ingredients need attention"
          article_ [class_ "stat-card impact-card"] $ do
            div_ [class_ "stat-icon yellow-icon"] "✳"
            p_ [class_ "stat-label"] "Your little impact"
            p_ [class_ "stat-value"] "4.2 kg"
            p_ [class_ "stat-note"] "food waste avoided this month"

        section_ [class_ "content-grid"] $ do
          article_ [class_ "panel pantry-panel", id_ "pantry"] $ do
            div_ [class_ "panel-heading"] $ do
              div_ $ do
                p_ [class_ "eyebrow dark-eyebrow"] "WHAT YOU HAVE"
                h2_ "In your pantry"
              a_ [class_ "text-link", href_ "#pantry"] $
                toHtml ("View all " <> Text.pack (show (length pantryItems)) <> " →")
            ul_ [class_ "pantry-list"] (mapM_ renderPantryItem pantryItems)
            a_ [class_ "add-link", href_ "#add-item"] $ do
              span_ [class_ "plus-icon"] "+"
              " Add an ingredient"

          article_ [class_ "panel recipe-panel", id_ "recipes"] $ do
            div_ [class_ "panel-heading"] $ do
              div_ $ do
                p_ [class_ "eyebrow dark-eyebrow"] "MADE FOR YOUR INGREDIENTS"
                h2_ "A few good ideas"
              a_ [class_ "text-link", href_ "#all-recipes"] "All recipes →"
            let availableIngredients = map itemName pantryItems
            div_ [class_ "recipe-list"] $
              mapM_ (recipeCard availableIngredients) (rankRecipes availableIngredients recipes)

        section_ [class_ "panel add-panel", id_ "add-item"] $ do
          div_ [class_ "panel-heading"] $ do
            div_ $ do
              p_ [class_ "eyebrow dark-eyebrow"] "KEEP YOUR PANTRY UP TO DATE"
              h2_ "Add an ingredient"
          maybe mempty (\message -> p_ [class_ "form-error"] (toHtml message)) formError
          form_ [class_ "add-form", method_ "post", action_ "/pantry"] $ do
            div_ [class_ "form-field"] $ do
              label_ [for_ "ingredient-name"] "Ingredient name"
              input_ [id_ "ingredient-name", name_ "name", type_ "text", placeholder_ "e.g. Red bell pepper", required_ "required"]
            div_ [class_ "form-field"] $ do
              label_ [for_ "ingredient-amount"] "Quantity"
              input_ [id_ "ingredient-amount", name_ "amount", type_ "text", placeholder_ "e.g. 2 pieces", required_ "required"]
            div_ [class_ "form-field"] $ do
              label_ [for_ "ingredient-days"] "Days until best before"
              input_ [id_ "ingredient-days", name_ "daysLeft", type_ "number", min_ "0", placeholder_ "e.g. 4", required_ "required"]
            button_ [class_ "submit-button", type_ "submit"] "Add to pantry"

        footer_ [class_ "footer"] $ do
          span_ "FreshStart"
          span_ "Small choices make a fresher kitchen."

renderPantryItem :: PantryItem -> Html ()
renderPantryItem item =
  li_ [class_ "pantry-item"] $ do
    span_ [class_ "food-emoji"] (toHtml (itemEmoji item))
    div_ [class_ "food-info"] $ do
      p_ [class_ "food-name"] (toHtml (itemName item))
      p_ [class_ "food-amount"] (toHtml (itemAmount item))
    div_ [class_ "expiry-info"] $ do
      span_
        [class_ ("expiry-pill " <> urgencyClass expiry)]
        (toHtml (expiryLabel (itemDaysLeft item)))
      span_ [class_ "expiry-caption"] "best before"
  where
    expiry = expiryStatus (itemDaysLeft item)

recipeCard :: [Text] -> Recipe -> Html ()
recipeCard available recipe =
  article_ [class_ "recipe-card"] $ do
    div_ [class_ ("recipe-visual " <> recipeStyle recipe)] (toHtml (recipeIcon recipe))
    div_ [class_ "recipe-info"] $ do
      p_ [class_ "recipe-match"] (toHtml (Text.pack (show (recipeMatchPercent available recipe)) <> "% match"))
      h3_ (toHtml (recipeName recipe))
      p_ [class_ "recipe-description"] (toHtml (recipeDescription recipe))
      p_ [class_ "recipe-duration"] $ do
        span_ "◷ "
        toHtml (recipeDuration recipe)

recipeIcon :: Recipe -> Text
recipeIcon recipe
  | recipeStyle recipe == "mint" = "🥑"
  | recipeStyle recipe == "lavender" = "🥬"
  | otherwise = "🍅"
