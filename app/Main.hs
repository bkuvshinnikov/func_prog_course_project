{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (bracket)
import Control.Monad.IO.Class (liftIO)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LazyText
import Database.MongoDB (genObjectId)
import FreshStart.Domain
import FreshStart.MongoStore
import Lucid
import Network.HTTP.Types.Status (status400)
import System.Environment (lookupEnv)
import Web.Scotty (ActionM, file, formParam, get, header, html, post, redirect, scotty, setHeader, status)

samplePantryItems :: [PantryItem]
samplePantryItems =
  [ PantryItem "sample-avocado" "🥑" "Avocado" "2 pieces" 0
  , PantryItem "sample-spinach" "🥬" "Baby spinach" "120 g" 1
  , PantryItem "sample-tomatoes" "🍅" "Cherry tomatoes" "1 cup" 3
  , PantryItem "sample-yogurt" "🥛" "Greek yogurt" "350 g" 5
  ]

recipes :: [Recipe]
recipes =
  [ Recipe "Creamy avocado toast" "Uses your avocado" "15 min" ["Avocado", "Bread", "Lemon"] "mint"
  , Recipe "Green garden omelette" "Spinach + pantry staples" "20 min" ["Baby spinach", "Eggs", "Feta"] "lavender"
  , Recipe "Tomato yogurt bowl" "Cherry tomatoes + yogurt" "10 min" ["Cherry tomatoes", "Greek yogurt"] "peach"
  ]

main :: IO ()
main = do
  username <- lookupEnv "APP_USERNAME"
  password <- lookupEnv "APP_PASSWORD"
  secureCookie <- lookupEnv "APP_COOKIE_SECURE"
  bracket (openPantryStore samplePantryItems) closePantryStore $ \pantryStore -> do
    sessions <- newIORef []
    scotty 3000 $ do
      get "/login" $ html (renderText (loginPage (authSetupMessage username password)))
      post "/login" $ do
        submittedUsername <- formParam "username"
        submittedPassword <- formParam "password"
        case (username, password) of
          (Just expectedUsername, Just expectedPassword)
            | Text.unpack submittedUsername == expectedUsername && Text.unpack submittedPassword == expectedPassword -> do
                token <- liftIO (Text.pack . show <$> genObjectId)
                liftIO (modifyIORef' sessions (token :))
                let secureAttribute = if secureCookie == Just "true" then "; Secure" else ""
                setHeader "Set-Cookie" ("freshstart_session=" <> LazyText.fromStrict token <> "; Path=/; HttpOnly; SameSite=Lax; Max-Age=28800" <> secureAttribute)
                redirect "/"
          _ -> do
            status status400
            html (renderText (loginPage (Just (maybe "The username or password is incorrect." id (authSetupMessage username password)))))
      post "/logout" $ do
        token <- sessionToken
        liftIO (maybe (pure ()) (removeSession sessions) token)
        setHeader "Set-Cookie" "freshstart_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        redirect "/login"
      get "/" $ do
        loggedIn <- isLoggedIn sessions
        if not loggedIn then redirect "/login" else do
          currentPantry <- liftIO (readPantryItems pantryStore)
          html (renderText (homePage currentPantry Nothing))
      post "/pantry" $ do
        loggedIn <- isLoggedIn sessions
        if not loggedIn then redirect "/login" else do
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
      post "/pantry/edit" $ do
        loggedIn <- isLoggedIn sessions
        if not loggedIn then redirect "/login" else do
          identifier <- formParam "itemId"
          currentPantry <- liftIO (readPantryItems pantryStore)
          case findPantryItem identifier currentPantry of
            Nothing -> redirect "/"
            Just item -> html (renderText (editPage item Nothing))
      post "/pantry/update" $ do
        loggedIn <- isLoggedIn sessions
        if not loggedIn then redirect "/login" else do
          identifier <- formParam "itemId"
          name <- formParam "name"
          amount <- formParam "amount"
          daysLeft <- formParam "daysLeft"
          currentPantry <- liftIO (readPantryItems pantryStore)
          case findPantryItem identifier currentPantry of
            Nothing -> redirect "/"
            Just oldItem -> case validatePantryItem name amount daysLeft of
              Left message -> do
                status status400
                html (renderText (editPage oldItem (Just message)))
              Right edited -> do
                _ <- liftIO (updatePantryItem pantryStore edited {itemId = identifier, itemEmoji = itemEmoji oldItem})
                redirect "/"
      post "/pantry/delete" $ do
        loggedIn <- isLoggedIn sessions
        if not loggedIn then redirect "/login" else do
          identifier <- formParam "itemId"
          liftIO (deletePantryItem pantryStore identifier)
          redirect "/"
      get "/style.css" $ do
        setHeader "Content-Type" "text/css; charset=utf-8"
        file "static/style.css"

sessionToken :: ActionM (Maybe Text)
sessionToken = do
  cookieHeader <- header "Cookie"
  pure (cookieHeader >>= findCookieToken . LazyText.toStrict)

findCookieToken :: Text -> Maybe Text
findCookieToken cookies =
  case [Text.drop (Text.length cookieName + 1) part | rawPart <- Text.splitOn ";" cookies, let part = Text.strip rawPart, (cookieName, _) <- [Text.breakOn "=" part], cookieName == "freshstart_session"] of
    token : _ | not (Text.null token) -> Just token
    _ -> Nothing

isLoggedIn :: IORef [Text] -> ActionM Bool
isLoggedIn sessions = do
  token <- sessionToken
  liftIO $ case token of
    Nothing -> pure False
    Just value -> elem value <$> readIORef sessions

removeSession :: IORef [Text] -> Text -> IO ()
removeSession sessions token = modifyIORef' sessions (filter (/= token))

findPantryItem :: Text -> [PantryItem] -> Maybe PantryItem
findPantryItem identifier = findFirst ((== identifier) . itemId)

findFirst :: (a -> Bool) -> [a] -> Maybe a
findFirst _ [] = Nothing
findFirst predicate (item : rest)
  | predicate item = Just item
  | otherwise = findFirst predicate rest

authSetupMessage :: Maybe String -> Maybe String -> Maybe Text
authSetupMessage (Just _) (Just _) = Nothing
authSetupMessage _ _ = Just "Set APP_USERNAME and APP_PASSWORD in .env before signing in."

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
        form_ [class_ "logout-form", method_ "post", action_ "/logout"] $
          button_ [class_ "profile", type_ "submit", title_ "Log out"] "B"

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
    div_ [class_ "item-actions"] $ do
      form_ [method_ "post", action_ "/pantry/edit"] $ do
        input_ [type_ "hidden", name_ "itemId", value_ (itemId item)]
        button_ [class_ "item-action edit-action", type_ "submit"] "Edit"
      form_ [method_ "post", action_ "/pantry/delete", onsubmit_ "return confirm('Delete this ingredient?')"] $ do
        input_ [type_ "hidden", name_ "itemId", value_ (itemId item)]
        button_ [class_ "item-action delete-action", type_ "submit"] "Delete"
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

loginPage :: Maybe Text -> Html ()
loginPage formError = do
  doctype_
  html_ [lang_ "en"] $ do
    head_ $ do
      meta_ [charset_ "utf-8"]
      meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
      title_ "Sign in — FreshStart"
      link_ [rel_ "stylesheet", href_ "/style.css"]
    body_ [class_ "auth-body"] $ do
      main_ [class_ "auth-card"] $ do
        a_ [class_ "brand auth-brand", href_ "/login"] $ do
          span_ [class_ "brand-mark"] "f"
          span_ "freshstart"
        p_ [class_ "eyebrow dark-eyebrow"] "A FRESH START FOR YOUR KITCHEN"
        h1_ "Welcome back"
        p_ [class_ "auth-description"] "Sign in to manage your pantry and discover recipes."
        maybe mempty (\message -> p_ [class_ "form-error"] (toHtml message)) formError
        form_ [class_ "auth-form", method_ "post", action_ "/login"] $ do
          div_ [class_ "form-field"] $ do
            label_ [for_ "username"] "Username"
            input_ [id_ "username", name_ "username", type_ "text", autocomplete_ "username", required_ "required", autofocus_]
          div_ [class_ "form-field"] $ do
            label_ [for_ "password"] "Password"
            input_ [id_ "password", name_ "password", type_ "password", autocomplete_ "current-password", required_ "required"]
          button_ [class_ "submit-button auth-submit", type_ "submit"] "Sign in"
        p_ [class_ "auth-footnote"] "Your pantry is waiting."

editPage :: PantryItem -> Maybe Text -> Html ()
editPage item formError = do
  doctype_
  html_ [lang_ "en"] $ do
    head_ $ do
      meta_ [charset_ "utf-8"]
      meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
      title_ "Edit ingredient — FreshStart"
      link_ [rel_ "stylesheet", href_ "/style.css"]
    body_ [class_ "auth-body"] $ do
      main_ [class_ "edit-card"] $ do
        a_ [class_ "brand", href_ "/"] $ do
          span_ [class_ "brand-mark"] "f"
          span_ "freshstart"
        p_ [class_ "eyebrow dark-eyebrow"] "YOUR PANTRY, YOUR WAY"
        h1_ "Edit ingredient"
        p_ [class_ "auth-description"] "Update the quantity or best-before date."
        maybe mempty (\message -> p_ [class_ "form-error"] (toHtml message)) formError
        form_ [class_ "auth-form", method_ "post", action_ "/pantry/update"] $ do
          input_ [type_ "hidden", name_ "itemId", value_ (itemId item)]
          div_ [class_ "form-field"] $ do
            label_ [for_ "edit-name"] "Ingredient name"
            input_ [id_ "edit-name", name_ "name", type_ "text", value_ (itemName item), required_ "required"]
          div_ [class_ "form-field"] $ do
            label_ [for_ "edit-amount"] "Quantity"
            input_ [id_ "edit-amount", name_ "amount", type_ "text", value_ (itemAmount item), required_ "required"]
          div_ [class_ "form-field"] $ do
            label_ [for_ "edit-days"] "Days until best before"
            input_ [id_ "edit-days", name_ "daysLeft", type_ "number", min_ "0", value_ (Text.pack (show (itemDaysLeft item))), required_ "required"]
          div_ [class_ "edit-actions"] $ do
            a_ [class_ "cancel-button", href_ "/"] "Cancel"
            button_ [class_ "submit-button", type_ "submit"] "Save changes"
