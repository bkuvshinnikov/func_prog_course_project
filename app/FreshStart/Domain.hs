{-# LANGUAGE OverloadedStrings #-}

module FreshStart.Domain
  ( ExpiryStatus (..)
  , Recipe (..)
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
