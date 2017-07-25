{-# LANGUAGE FlexibleContexts #-}
module QuickSpec.Explore where

import QuickSpec.Explore.Terms
import QuickSpec.Testing
import QuickSpec.Pruning
import QuickSpec.Term
import QuickSpec.Type
import QuickSpec.Utils

baseTerms :: (Ord f, Typeable f, Ord a) => (Term f -> a) -> [f] -> [Type] -> [Term f]
baseTerms measure funs tys =
  sortBy' measure $
    [App f [] | f <- funs] ++
    zipWith (\ty n -> Var (V ty n)) (concatMap (replicate 3) tys) [0..]

moreTerms :: (Ord a, Apply (Term f)) => (Term f -> a) -> [[Term f]] -> [Term f]
moreTerms measure tss =
  sortBy' measure $
    [ v
    | i <- [0..n-1],
      t <- tss !! i,
      u <- tss !! (n-i),
      Just v <- [tryApply t u] ]
  where
    n = length tss

quickSpec :: (Ord a, Ord f, Typeable f, Ord result, Apply (Term f), PrettyTerm f) =>
  (Term f -> a) ->
  (Term f -> testcase -> result) ->
  Tester testcase (Term f) ->
  Pruner (Term f) ->
  Int -> [f] -> [Type] -> IO ()
quickSpec measure eval tester pruner size funs tys = do
  let state0 = initialState eval tester pruner

  loop state0 size [[]] [] (baseTerms measure funs tys)
  where
    loop _ 1 _ _ [] = return ()
    loop state n tss ts [] =
      loop state (n-1) uss [] (moreTerms measure uss)
      where
        uss = tss ++ [ts]
    loop state n tss us (t:ts) = do
      let (state', ts', props) = explore t state
      mapM_ prettyPrint props
      loop state' n tss (ts' ++ us) ts
