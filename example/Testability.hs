{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import           Control.Monad     (join)
import           Reflex
import           Reflex.Host.Basic (basicHostWithStaticEvents)


main :: IO ()
main = do
  output :: [[Maybe Int]] <-
    basicHostWithStaticEvents [1..10 :: Int] $ \ev -> do
      -- simple state that takes input event and adds 1 to it
      state <- foldDyn (\x -> const (x+1)) 0 ev
      return $ updated state
  print "last output is:"
  print $ last $ join output
