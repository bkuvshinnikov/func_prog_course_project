{-# LANGUAGE OverloadedStrings #-}

module FreshStart.MongoStore
  ( PantryStore
  , openPantryStore
  , closePantryStore
  , readPantryItems
  , addPantryItem
  ) where

import Control.Exception (bracketOnError)
import Control.Monad (unless, when)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import qualified Data.Text as Text
import Database.MongoDB
import FreshStart.Domain (PantryItem (..))
import Network.URI (URI (..), URIAuth (..), parseURI, unEscapeString)
import System.Environment (lookupEnv)

data PantryStore
  = MemoryStore (IORef [PantryItem])
  | AtlasStore ReplicaSet Pipe Text

data MongoConfig = MongoConfig
  { mongoHost :: String
  , mongoUsername :: Text
  , mongoPassword :: Text
  , configDatabase :: Text
  }

openPantryStore :: [PantryItem] -> IO PantryStore
openPantryStore initialItems = do
  uri <- lookupEnv "MONGODB_URI"
  case uri of
    Nothing -> do
      putStrLn "MONGODB_URI is not set; using in-memory sample data."
      MemoryStore <$> newIORef initialItems
    Just connectionString -> do
      config <- either (ioError . userError . Text.unpack) pure (parseMongoConfig connectionString)
      replicaSet <- openReplicaSetSRV' (mongoHost config)
      store <- bracketOnError (connectAndSeed replicaSet config initialItems) (const (closeReplicaSet replicaSet)) pure
      putStrLn "Connected to MongoDB Atlas."
      pure store

closePantryStore :: PantryStore -> IO ()
closePantryStore store = case store of
  MemoryStore _ -> pure ()
  AtlasStore replicaSet _ _ -> closeReplicaSet replicaSet

readPantryItems :: PantryStore -> IO [PantryItem]
readPantryItems store = case store of
  MemoryStore items -> readIORef items
  AtlasStore _ pipe database -> loadItems pipe database

addPantryItem :: PantryStore -> PantryItem -> IO ()
addPantryItem store item = case store of
  MemoryStore items -> modifyIORef' items (item :)
  AtlasStore _ pipe database -> saveItem pipe database item

connectAndSeed :: ReplicaSet -> MongoConfig -> [PantryItem] -> IO PantryStore
connectAndSeed replicaSet config initialItems = do
  pipe <- primary replicaSet
  authenticated <- access pipe master "admin" (authSCRAMSHA256 (mongoUsername config) (mongoPassword config))
  unless authenticated (ioError (userError "MongoDB authentication failed."))
  items <- loadItems pipe (configDatabase config)
  when (null items) (mapM_ (saveItem pipe (configDatabase config)) initialItems)
  pure (AtlasStore replicaSet pipe (configDatabase config))

loadItems :: Pipe -> Text -> IO [PantryItem]
loadItems pipe database = do
  documents <- access pipe master database (rest =<< find (select [] "pantry"))
  pure (map documentToPantryItem documents)

saveItem :: Pipe -> Text -> PantryItem -> IO ()
saveItem pipe database item = do
  _ <- access pipe master database $ insert_ "pantry"
    [ "emoji" =: itemEmoji item
    , "name" =: itemName item
    , "amount" =: itemAmount item
    , "daysLeft" =: itemDaysLeft item
    ]
  pure ()

documentToPantryItem :: Document -> PantryItem
documentToPantryItem document = PantryItem
  { itemEmoji = "emoji" `at` document
  , itemName = "name" `at` document
  , itemAmount = "amount" `at` document
  , itemDaysLeft = "daysLeft" `at` document
  }

parseMongoConfig :: String -> Either Text MongoConfig
parseMongoConfig rawUri = do
  uri <- maybe (Left "MONGODB_URI is not a valid MongoDB URI.") Right (parseURI rawUri)
  if uriScheme uri /= "mongodb+srv:"
    then Left "MONGODB_URI must use the mongodb+srv scheme for Atlas."
    else pure ()
  authority <- maybe (Left "MONGODB_URI is missing its cluster host.") Right (uriAuthority uri)
  when (null (uriRegName authority)) (Left "MONGODB_URI is missing its cluster host.")
  credentials <- parseCredentials (uriUserInfo authority)
  let databaseName = takeWhile (\character -> character /= '?' && character /= '/')
        (dropWhile (== '/') (uriPath uri))
      selectedDatabase = if null databaseName then "freshstart" else unEscapeString databaseName
  pure MongoConfig
    { mongoHost = uriRegName authority
    , mongoUsername = Text.pack (fst credentials)
    , mongoPassword = Text.pack (snd credentials)
    , configDatabase = Text.pack selectedDatabase
    }

parseCredentials :: String -> Either Text (String, String)
parseCredentials userInfo = case break (== ':') (takeWhile (/= '@') userInfo) of
  (username, ':' : password)
    | null username || null password -> Left "MONGODB_URI must include a database username and password."
    | otherwise -> Right (unEscapeString username, unEscapeString password)
  _ -> Left "MONGODB_URI must include a database username and password."
