{-# LANGUAGE OverloadedStrings #-}

module FreshStart.Domain
  ( ExpiryStatus (..)
  , PantryItem (..)
  , Recipe (..)
  , validatePantryItem
  , expiryStatus
  , expiryLabel
  , urgencyClass
  , countItemsNeedingAttention
  , recipeMatchPercent
  , rankRecipes
  ) where

import Data.List (sortOn)
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as Text
import Text.Read (readMaybe)

data ExpiryStatus
  = Expired
  | UseToday
  | UseTomorrow
  | UseSoon
  | Fresh
  deriving (Eq, Show)

data Recipe = Recipe
  { recipeName :: Text
  , recipeDescription :: Text
  , recipeDuration :: Text
  , recipeIngredients :: [Text]
  , recipeStyle :: Text
  }
  deriving (Eq, Show)

data PantryItem = PantryItem
  { itemEmoji :: Text
  , itemName :: Text
  , itemAmount :: Text
  , itemDaysLeft :: Int
  }
  deriving (Eq, Show)

validatePantryItem :: Text -> Text -> Text -> Either Text PantryItem
validatePantryItem rawName rawAmount rawDaysLeft
  | Text.null name = Left "Enter an ingredient name."
  | Text.null amount = Left "Enter the ingredient quantity."
  | otherwise = case readMaybe (Text.unpack (Text.strip rawDaysLeft)) of
      Nothing -> Left "Enter the number of days until the best-before date."
      Just daysLeft
        | daysLeft < 0 -> Left "Days until the best-before date cannot be negative."
        | otherwise -> Right (PantryItem "🥗" name amount daysLeft)
  where
    name = Text.strip rawName
    amount = Text.strip rawAmount

expiryStatus :: Int -> ExpiryStatus
expiryStatus daysLeft
  | daysLeft < 0 = Expired
  | daysLeft == 0 = UseToday
  | daysLeft == 1 = UseTomorrow
  | daysLeft <= 3 = UseSoon
  | otherwise = Fresh

expiryLabel :: Int -> Text
expiryLabel daysLeft
  | daysLeft < 0 = Text.pack (show (abs daysLeft)) <> " days overdue"
  | daysLeft == 0 = "Today"
  | daysLeft == 1 = "Tomorrow"
  | otherwise = "In " <> Text.pack (show daysLeft) <> " days"

urgencyClass :: ExpiryStatus -> Text
urgencyClass status = case status of
  Expired -> "expired"
  UseToday -> "urgent"
  UseTomorrow -> "soon"
  UseSoon -> "soon"
  Fresh -> "fresh"

countItemsNeedingAttention :: [Int] -> Int
countItemsNeedingAttention = length . filter ((/= Fresh) . expiryStatus)

recipeMatchPercent :: [Text] -> Recipe -> Int
recipeMatchPercent available recipe
  | null required = 0
  | otherwise = (100 * matchingCount) `div` length required
  where
    required = map normalize (recipeIngredients recipe)
    availableIngredients = map normalize available
    matchingCount = length (filter (`elem` availableIngredients) required)
    normalize = Text.toCaseFold . Text.strip

rankRecipes :: [Text] -> [Recipe] -> [Recipe]
rankRecipes available = sortOn (Down . recipeMatchPercent available)
