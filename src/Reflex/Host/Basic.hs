{-|
Module      : Reflex.Host.Basic
Copyright   : (c) 2019 Commonwealth Scientific and Industrial Research Organisation (CSIRO)
License     : BSD-3
Maintainer  : dave.laing.80@gmail.com

'BasicGuest' provides instances that most `reflex` programs need:

* 'MonadIO'
* 'MonadFix'
* 'MonadSample'
* 'MonadHold'
* 'NotReady'
* 'PostBuild'
* 'PerformEvent' — @'Performable' ('BasicGuest' t m)@ has 'MonadIO'
* 'TriggerEvent'
* 'Adjustable'

For some simple usage examples, see
<https://github.com/qfpl/reflex-basic-host/tree/master/example the examples directory>

-}

{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}

module Reflex.Host.Basic
  ( BasicGuest
  , BasicGuestConstraints
  , basicHostWithQuit
  , basicHostForever
  , repeatUntilQuit
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan (newChan, readChan)
import Control.Concurrent.STM.TVar (newTVarIO, writeTVar, readTVarIO)
import Control.Lens ((<&>))
import Control.Monad (void, when, unless)
import Control.Monad.Fix (MonadFix)
import Control.Monad.Primitive (PrimMonad)
import Control.Monad.Ref (MonadRef(..))
import Control.Monad.STM (atomically)
import Control.Monad.Trans (MonadIO(..), MonadTrans(..))
import Data.Dependent.Sum (DSum(..), (==>))
import Data.Foldable (for_, traverse_)
import Data.Functor.Identity (Identity)
import Data.Maybe (catMaybes, isJust)
import Data.Traversable (for)
import Reflex
import Reflex.Host.Class

type BasicGuestConstraints t (m :: * -> *) =
  ( MonadReflexHost t m
  , MonadHold t m
  , MonadSample t m
  , Ref m ~ Ref IO
  , MonadRef (HostFrame t)
  , Ref (HostFrame t) ~ Ref IO
  , MonadIO (HostFrame t)
  , PrimMonad (HostFrame t)
  , MonadIO m
  , MonadFix m
  )

newtype BasicGuest t (m :: * -> *) a =
  BasicGuest {
    unBasicGuest :: PostBuildT t (TriggerEventT t (PerformEventT t m)) a
  } deriving (Functor, Applicative, Monad, MonadFix)

instance (ReflexHost t, MonadIO (HostFrame t)) => MonadIO (BasicGuest t m) where
  {-# INLINEABLE liftIO #-}
  liftIO = BasicGuest . liftIO

instance ReflexHost t => MonadSample t (BasicGuest t m) where
  {-# INLINABLE sample #-}
  sample = BasicGuest . lift . sample

instance (ReflexHost t, MonadHold t m) => MonadHold t (BasicGuest t m) where
  {-# INLINABLE hold #-}
  hold v0 = BasicGuest . lift . hold v0

  {-# INLINABLE holdDyn #-}
  holdDyn v0 = BasicGuest . lift . holdDyn v0

  {-# INLINABLE holdIncremental #-}
  holdIncremental v0 = BasicGuest . lift . holdIncremental v0

  {-# INLINABLE buildDynamic #-}
  buildDynamic a0 = BasicGuest . lift . buildDynamic a0

  {-# INLINABLE headE #-}
  headE = BasicGuest . lift . headE

instance ReflexHost t => PostBuild t (BasicGuest t m) where
  {-# INLINABLE getPostBuild #-}
  getPostBuild = BasicGuest getPostBuild

instance
  ( ReflexHost t
  , MonadRef (HostFrame t)
  , Ref (HostFrame t) ~ Ref IO
  ) => TriggerEvent t (BasicGuest t m) where

  {-# INLINABLE newTriggerEvent #-}
  newTriggerEvent = BasicGuest $ lift newTriggerEvent

  {-# INLINABLE newTriggerEventWithOnComplete #-}
  newTriggerEventWithOnComplete =
    BasicGuest $ lift newTriggerEventWithOnComplete

  {-# INLINABLE newEventWithLazyTriggerWithOnComplete #-}
  newEventWithLazyTriggerWithOnComplete =
    BasicGuest . lift . newEventWithLazyTriggerWithOnComplete

instance
  ( ReflexHost t
  , Ref m ~ Ref IO
  , MonadRef (HostFrame t)
  , Ref (HostFrame t) ~ Ref IO
  , MonadIO (HostFrame t)
  , PrimMonad (HostFrame t)
  , MonadIO m
  ) => PerformEvent t (BasicGuest t m) where

  type Performable (BasicGuest t m) = HostFrame t

  {-# INLINABLE performEvent_ #-}
  performEvent_ = BasicGuest . lift . lift . performEvent_

  {-# INLINABLE performEvent #-}
  performEvent = BasicGuest . lift . lift . performEvent

instance
  ( ReflexHost t
  , Ref m ~ Ref IO
  , MonadHold t m
  , PrimMonad (HostFrame t)
  ) => Adjustable t (BasicGuest t m) where

  {-# INLINABLE runWithReplace #-}
  runWithReplace a0 a' = BasicGuest $
    runWithReplace (unBasicGuest a0) (fmap unBasicGuest a')

  {-# INLINABLE traverseIntMapWithKeyWithAdjust #-}
  traverseIntMapWithKeyWithAdjust f dm0 dm' = BasicGuest $
    traverseIntMapWithKeyWithAdjust (\k v -> unBasicGuest (f k v)) dm0 dm'

  {-# INLINABLE traverseDMapWithKeyWithAdjust #-}
  traverseDMapWithKeyWithAdjust f dm0 dm' = BasicGuest $
    traverseDMapWithKeyWithAdjust (\k v -> unBasicGuest (f k v)) dm0 dm'

  {-# INLINABLE traverseDMapWithKeyWithAdjustWithMove #-}
  traverseDMapWithKeyWithAdjustWithMove f dm0 dm' = BasicGuest $
    traverseDMapWithKeyWithAdjustWithMove (\k v -> unBasicGuest (f k v)) dm0 dm'

instance ReflexHost t => NotReady t (BasicGuest t m) where
  {-# INLINABLE notReadyUntil #-}
  notReadyUntil _ = pure ()

  {-# INLINABLE notReady #-}
  notReady = pure ()

-- | Run a 'BasicGuest' without a quit 'Event'.
basicHostForever
  :: (forall t m. BasicGuestConstraints t m => BasicGuest t m a)
  -> IO a
basicHostForever guest = basicHostWithQuit $ guest <&> (,never)

-- | Run a 'BasicGuest'.
--
-- The program will exit when the 'Event' returned by the 'BasicGuest' fires
basicHostWithQuit
  :: (forall t m. BasicGuestConstraints t m => BasicGuest t m (a, Event t ()))
  -> IO a
basicHostWithQuit (BasicGuest guest) = do
  performEventChan <- newChan
  (postBuild, postBuildTriggerRef) <- runSpiderHost newEventWithTriggerRef

  -- Unpack the guest
  ((a, eQuit), FireCommand fire) <- runSpiderHost . hostPerformEventT $
    runTriggerEventT (runPostBuildT guest postBuild) performEventChan

  hQuit <- runSpiderHost $ subscribeEvent eQuit
  rHasQuit <- newRef False -- When to shut down
  let
    runFrameAndCheckQuit firings = do
      lmQuit <- fire firings $ readEvent hQuit >>= sequenceA
      when (any isJust lmQuit) $ writeRef rHasQuit True

  -- If anyone is listening to PostBuild, fire it
  readRef postBuildTriggerRef
    >>= traverse_ (\t -> runSpiderHost $ runFrameAndCheckQuit [t ==> ()])

  let
    loop = do
      hasQuit <- readRef rHasQuit
      unless hasQuit $ do
        eventsAndTriggers <- readChan performEventChan

        runSpiderHost $ do
          let
            prepareFiring
              :: DSum (EventTriggerRef t) TriggerInvocation
              -> IO (Maybe (DSum (EventTrigger t) Identity))
            prepareFiring (EventTriggerRef er :=> TriggerInvocation x _)
               = readRef er <&> fmap (==> x)

          liftIO (catMaybes <$> for eventsAndTriggers prepareFiring)
            >>= runFrameAndCheckQuit

          -- Fire callbacks for each event we triggered this frame
          liftIO . for_ eventsAndTriggers $
            \(_ :=> TriggerInvocation _ cb) -> cb
        loop

  loop
  pure a

-- | Augment a 'BasicGuest' with an action that is repeatedly run until
-- the provided event fires
--
-- Example - providing a \'tick\' 'Event' to a network
--
-- @
-- myNetwork
--   :: (Reflex t, MonadHold t m, MonadFix m)
--   => Event t ()
--   -> m (Dynamic t Int)
-- myNetwork eTick = count eTick
--
-- myGuest :: BasicGuestConstraints t m => BasicGuest t m ((), Event t ())
-- myGuest = do
--   (eTick, sendTick) <- newTriggerEvent
--   dCount <- myNetwork eTick
--   let
--     eCountUpdated = updated dCount
--     eQuit = () <$ ffilter (== 5) eCountUpdated
--   repeatUntilQuit eQuit (threadDelay 1000000 *> sendTick ())
--   performEvent_ $ liftIO . print \<$\> eCountUpdated
--   pure ((), eQuit)
--
-- main :: IO ()
-- main = basicHostWithQuit myGuest
-- @
repeatUntilQuit
  :: BasicGuestConstraints t m
  => IO a -- ^ Action to repeatedly run
  -> Event t () -- ^ 'Event' to stop the action
  -> BasicGuest t m ()
repeatUntilQuit act eQuit = do
  ePostBuild <- getPostBuild
  tHasQuit <- liftIO $ newTVarIO False

  let
    loop = do
      hasQuit <- readTVarIO tHasQuit
      unless hasQuit $ void act *> loop

  performEvent_ $ liftIO (void $ forkIO loop) <$ ePostBuild
  performEvent_ $ liftIO (atomically $ writeTVar tHasQuit True) <$ eQuit
