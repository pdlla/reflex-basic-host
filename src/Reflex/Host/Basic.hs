{-|
Module      : Reflex.Host.Basic
Copyright   : (c) 2019 Commonwealth Scientific and Industrial Research Organisation (CSIRO)
License     : BSD-3
Maintainer  : dave.laing.80@gmail.com, jack.kelly@data61.csiro.au

'BasicGuest' provides instances that most Reflex programs need:

* 'MonadIO'
* 'MonadFix'
* 'MonadSample'
* 'MonadHold'
* 'NotReady'
* 'PostBuild'
* 'PerformEvent' — @'Performable' ('BasicGuest' t m)@ has 'MonadIO'
* 'TriggerEvent'
* 'Adjustable'

For some usage examples, see
<https://github.com/qfpl/reflex-basic-host/tree/master/example the example directory>.

-}

{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}

module Reflex.Host.Basic
  (
  -- * Running the host
    basicHostWithQuit
  , basicHostForever
  , basicHostWithStaticEvents

  -- * Types
  , BasicGuest
  , BasicGuestConstraints

  -- * Utilities
  , repeatUntilQuit
  , repeatUntilQuit_
  ) where

import           Control.Concurrent          (forkIO)
import           Control.Concurrent.Chan     (newChan, readChan)
import           Control.Concurrent.STM.TVar (newTVarIO, readTVarIO, writeTVar)
import           Control.Exception.Base      (BlockedIndefinitelyOnMVar (..),
                                              catch)
import           Control.Lens                ((<&>))
import           Control.Monad               (forM, unless, void, when)
import           Control.Monad.Fix           (MonadFix)
import           Control.Monad.Primitive     (PrimMonad)
import           Control.Monad.Ref           (MonadRef (..))
import           Control.Monad.STM           (atomically)
import           Control.Monad.Trans         (MonadIO (..), MonadTrans (..))
import           Data.Dependent.Sum          (DSum (..), (==>))
import           Data.Foldable               (for_, traverse_)
import           Data.Functor.Identity       (Identity)
import           Data.Maybe                  (catMaybes, isJust)
import           Data.Traversable            (for)
import           Reflex
import           Reflex.Host.Class

-- | Constraints provided by a 'BasicGuest', when run by
-- 'basicHostWithQuit' or 'basicHostForever'.
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

-- | The basic guest type. Try not to code against it directly;
-- instead ask for the features you need MTL-style:
--
-- @
-- myFunction :: (Reflex t, MonadHold m) => ...
-- @
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
--
-- @
-- basicHostForever guest = 'basicHostWithQuit' $ never <$ guest
-- @
basicHostForever
  :: (forall t m. BasicGuestConstraints t m => BasicGuest t m ())
  -> IO ()
basicHostForever guest = basicHostWithQuit $ never <$ guest

-- | Run a 'BasicGuest', and return when the 'Event' returned by the
-- 'BasicGuest' fires.
--
-- Each host runs on a separate spider timeline, so you can launch
-- multiple hosts via 'Control.Concurrent.forkIO' or
-- 'Control.Concurrent.forkOS' and they will not mutex each other.
--
-- NOTE: If you want to capture values from a build before the network
-- starts firing (e.g., to hand off event triggers to another thread),
-- populate an 'Control.Concurrent.MVar' (if threading) or
-- 'Data.IORef.IORef' as you build the network. If you receive errors
-- about untouchable type variables while doing this, add type
-- annotations to constrain the 'Control.Concurrent.MVar' or
-- 'Data.IORef.IORef' contents before passing them to the function
-- that returns your 'BasicGuest'. See the @Multithread.hs@ example
-- for a demonstration of this pattern, and where to put the type
-- annotations.
basicHostWithQuit
  :: (forall t m. BasicGuestConstraints t m => BasicGuest t m (Event t ()))
  -> IO ()
basicHostWithQuit guest =
  withSpiderTimeline $ runSpiderHostForTimeline $ do
    -- Unpack the guest, get the quit event, the result of building the
    -- network, and a function to kick off each frame.
    (postBuild, postBuildTriggerRef) <- newEventWithTriggerRef
    triggerEventChan <- liftIO newChan
    rHasQuit <- newRef False -- When to shut down
    (eQuit, FireCommand fire) <- hostPerformEventT
      . flip runTriggerEventT triggerEventChan
      . flip runPostBuildT postBuild
      $ unBasicGuest guest

    hQuit <- subscribeEvent eQuit
    let
      runFrameAndCheckQuit firings = do
        lmQuit <- fire firings $ readEvent hQuit >>= sequenceA
        when (any isJust lmQuit) $ writeRef rHasQuit True

    -- If anyone is listening to PostBuild, fire it
    readRef postBuildTriggerRef
      >>= traverse_ (\t -> runFrameAndCheckQuit [t ==> ()])

    let
      loop = do
        hasQuit <- readRef rHasQuit
        unless hasQuit $ do
          eventsAndTriggers <- liftIO $ readChan triggerEventChan

          let
            prepareFiring
              :: (MonadRef m, Ref m ~ Ref IO)
              => DSum (EventTriggerRef t) TriggerInvocation
              -> m (Maybe (DSum (EventTrigger t) Identity))
            prepareFiring (EventTriggerRef er :=> TriggerInvocation x _)
              = readRef er <&> fmap (==> x)

          catMaybes <$> for eventsAndTriggers prepareFiring
            >>= runFrameAndCheckQuit

          -- Fire callbacks for each event we triggered this frame
          liftIO . for_ eventsAndTriggers $
            \(_ :=> TriggerInvocation _ cb) -> cb
          loop
    loop

-- | Augment a 'BasicGuest' with an action that is repeatedly run
-- until the provided 'Event' fires. Each time the action completes,
-- the returned 'Event' will fire.
--
-- Example - providing a \'tick\' 'Event' to a network
--
-- @
-- myNetwork
--   :: (Reflex t, MonadHold t m, MonadFix m)
--   => Event t ()
--   -> m (Dynamic t Int)
-- myNetwork = count
--
-- myGuest :: BasicGuestConstraints t m => BasicGuest t m (Event t ())
-- myGuest = mdo
--   eTick <- repeatUntilQuit (void $ threadDelay 1000000) eQuit
--   let
--     eCountUpdated = updated dCount
--     eQuit = () <$ ffilter (==5) eCountUpdated
--   dCount <- myNetwork eTick
--
--   performEvent_ $ liftIO . print \<$\> eCountUpdated
--   pure eQuit
--
-- main :: IO ()
-- main = basicHostWithQuit myGuest
-- @
repeatUntilQuit
  :: BasicGuestConstraints t m
  => IO a -- ^ Action to repeatedly run
  -> Event t () -- ^ 'Event' to stop the action
  -> BasicGuest t m (Event t a)
repeatUntilQuit act eQuit = do
  ePostBuild <- getPostBuild
  tHasQuit <- liftIO $ newTVarIO False

  let
    go fire = loop where
      loop = do
        hasQuit <- readTVarIO tHasQuit
        unless hasQuit $ (act >>= fire) *> loop

  performEvent_ $ liftIO (atomically $ writeTVar tHasQuit True) <$ eQuit
  performEventAsync $ liftIO . void . forkIO . go <$ ePostBuild

-- | Like 'repeatUntilQuit', but it doesn't do anything with the
-- result of the action. May be a little more efficient if you don't
-- need it.
repeatUntilQuit_
  :: BasicGuestConstraints t m
  => IO a -- ^ Action to repeatedly run
  -> Event t () -- ^ 'Event' to stop the action
  -> BasicGuest t m ()
repeatUntilQuit_ act eQuit = do
  ePostBuild <- getPostBuild
  tHasQuit <- liftIO $ newTVarIO False

  let
    loop = do
      hasQuit <- readTVarIO tHasQuit
      unless hasQuit $ act *> loop

  performEvent_ $ liftIO (atomically $ writeTVar tHasQuit True) <$ eQuit
  performEvent_ $ liftIO (void $ forkIO loop) <$ ePostBuild





-- TODO change implementation of this to work with DMap k (Event t (k a)) and [DMap k Identity]
-- interface can stay the same since most use cases won't need DMap

-- | Run a 'BasicGuest' with list of inputs created from passed in method and
-- returns a list of outputs for each frame for each input.
--
-- The method takes an event that will fire once for each input in sequence
-- and returns a 'BasicGuest' which produces an output event that is tracked.
--
-- The output disregards outputs from 'PostBuild' events.
--
-- Each input value may trigger several frames. The results are collected in a
-- list for each input frame. Trigger events are also collected in the output
-- for the input value they happened to trigger on.
--
-- Asynchronously fired trigger events are not guaranteed to be processed.
--
-- If your network does not make use of 'performEvent' or external trigger
-- events then you can 'join' the final IO output for '[Maybe b]' which is the
-- output event value for each input value in the input list.
--
-- Also relevant comments for 'basicHostWithQuit' apply here too
basicHostWithStaticEvents
  :: forall a b. (Show a, Show b) =>
  [a] -- ^ list of input events to fire
  -> (forall t m. BasicGuestConstraints t m => Event t a -> BasicGuest t m (Event t b)) -- ^ function producing network from input events
  -> IO [[Maybe b]] -- ^ list of fired output events per input per frame that got processed for that input
basicHostWithStaticEvents inputs guestfn =
  withSpiderTimeline $ runSpiderHostForTimeline $ do
    liftIO $ print 1
    triggerEventChan <- liftIO newChan
    (postBuild, postBuildTriggerRef) <- newEventWithTriggerRef
    (inputEvent, inputEventTriggerRef) <- newEventWithTriggerRef
    (eOutput, FireCommand fire) <- hostPerformEventT
      . flip runTriggerEventT triggerEventChan
      . flip runPostBuildT postBuild
      $ unBasicGuest (guestfn inputEvent)
    liftIO $ print 2
    hOutput <- subscribeEvent eOutput
    liftIO $ print 3
    let
      runFrame firings = fire firings (readEvent hOutput >>= sequenceA)

    -- fire PostBuild event and ignore outputs
    readRef postBuildTriggerRef
      >>= traverse_ (\t -> runFrame [t ==> ()])
    liftIO $ print 4
    forM inputs $ \input -> do
      -- run network for input
      inputET <- readRef inputEventTriggerRef
      outputs <- case inputET of
        Nothing -> error "no input trigger ref, this should never happen"
        Just x  -> runFrame [x ==> input]

      liftIO $ print ("5 " <> show input)


      let
        prepareFiring
          :: (MonadRef m, Ref m ~ Ref IO)
          => DSum (EventTriggerRef t) TriggerInvocation
          -> m (Maybe (DSum (EventTrigger t) Identity))
        prepareFiring (EventTriggerRef er :=> TriggerInvocation x _)
          = readRef er <&> fmap (==> x)

      -- now run the network again if there are any trigger events
      eventsAndTriggers <- liftIO $ catch (readChan triggerEventChan) (\BlockedIndefinitelyOnMVar -> return [])
      liftIO $ print $ "6 " <> show (length eventsAndTriggers)
      triggerOutputs <- do
        triggers <- (catMaybes <$> for eventsAndTriggers prepareFiring)
        case triggers of
          [] -> return []
          _  -> runFrame triggers

      liftIO $ print 7
      -- fire IO callbacks for each event we triggered this frame
      liftIO . for_ eventsAndTriggers $
        \(_ :=> TriggerInvocation _ cb) -> cb
      liftIO $ print ("8 " <> show outputs <> " " <> show triggerOutputs)
      -- return collected output
      return $ outputs <> triggerOutputs
