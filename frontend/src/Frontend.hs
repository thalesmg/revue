{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
module Frontend where

import Prelude hiding (id, (.))

import Control.Category
import Control.Monad
import Data.Maybe (fromMaybe)
import Data.Monoid hiding ((<>))
import Data.Semigroup ((<>))
import Data.Text (Text)
import qualified Data.Text as T

import Language.Javascript.JSaddle
import Reflex.Dom.Core

import Obelisk.Frontend
import Obelisk.Route.Frontend

import Static

import Common.Route

import Frontend.Css (appCssStr)

title :: Text
title = "Sridhar Ratnakumar"

frontend :: Frontend (R Route)
frontend = Frontend
  { _frontend_head = do
      elAttr "base" ("href" =: "/") blank
      elAttr "meta" ("name" =: "viewport" <> "content" =: "width=device-width, initial-scale=1") blank
      elAttr "link" ("rel" =: "stylesheet" <> "type" =: "text/css" <> "href" =: static @"semantic.min.css") blank
      el "style" $ text appCssStr
      -- FIXME: Title should actually come from the Yaml metadata, but we fetch
      -- content in _frontend_body; how to access that Dynamic from here?
      el "title" $ subRoute_ $ \case
        Route_Home -> text title
        Route_Page -> dynText =<< fmap ((<> " - " <> title) . mconcat <$>) askRoute
  , _frontend_body = do
      divClass "ui container" $ do
        divClass "ui top attached inverted header" $ do
          evt <- click' $ el' "h1" $ text title
          tellEvent $ Endo (const $ Route_Home :/ ()) <$ evt
        divClass "ui attached segment" $
          elAttr "div" ("id" =: "content") $ do
            divClass "markdown" $ prerender (text "JavaScript is required to view this page.") $
              void $ elDynHtml' "div" =<< do
                e :: Event t Text <- fmap (switch . current) $ subRoute $ \case
                  Route_Home -> fetchContent (backendRoute BackendRoute_GetPage ["landing"])
                  Route_Page -> do
                    page :: Dynamic t [Text] <- fmap (traceDyn "askRoute" ) $ askRoute
                    switchHold never <=< dyn . ffor page $ fetchContent . backendRoute BackendRoute_GetPage
                -- Workaround a fetchContent bug (duplicate events) by using holdUniqDyn
                holdUniqDyn =<< holdDyn "Loading..." e
        divClass "ui secondary bottom attached segment" $ do
          divClass "footer" $ do
            elAttr "a" ("href" =: projectUrl) $ text "Powered by Haskell"
  , _frontend_notFoundRoute = \_ -> Route_Home :/ () -- TODO: not used i think
  }
  where
    projectUrl = "https://github.com/srid/revue" :: Text
    Right backendRouteValidEncoder = checkEncoder $ obeliskRouteEncoder backendRouteComponentEncoder backendRouteRestEncoder
    backendRoute c r = ("/" <>) $ T.intercalate "/" $ fst $ _validEncoder_encode backendRouteValidEncoder $ ObeliskRoute_App c :/ r

-- TODO: Move to Widget.hs

click'
  :: (HasDomEvent t target 'ClickTag, Functor m)
  => m (target, a)
  -> m (Event t (DomEventType target 'ClickTag))
click' = fmap (domEvent Click . fst)

-- TODO: change this to toplevel dynamic
fetchContent ::
  ( PostBuild t m
  , TriggerEvent t m
  , PerformEvent t m
  , MonadJSM (Performable m)
  , HasJSContext (Performable m)
  )
  => Text -> m (Event t Text)
fetchContent url = do
  let req = xhrRequest "GET" url def
  pb <- getPostBuild
  -- FIXME: Why is asyncReq firing 3 times?
  responses <- performRequestAsync $ req <$ pb
  pure $ ffor responses $ \resp -> do
    if _xhrResponse_status resp >= 200 && _xhrResponse_status resp < 300
      then fromMaybe "    fetchContent: Unknown error" $ _xhrResponse_responseText resp
      else "    fetchContent: 404"
