{-# OPTIONS_GHC -fwarn-missing-signatures #-}

{-# LANGUAGE CPP #-}

module Agda.TypeChecking.CompiledClause.Compile where

import Data.Maybe
import Data.Monoid
import qualified Data.Map as Map
import Data.List (genericReplicate, nubBy, findIndex)
import Data.Function

import Agda.Syntax.Common
import Agda.Syntax.Internal as I
import Agda.TypeChecking.CompiledClause
import Agda.TypeChecking.Coverage
import Agda.TypeChecking.Coverage.SplitTree
import Agda.TypeChecking.Monad
import Agda.TypeChecking.RecordPatterns
import Agda.TypeChecking.Substitute
import Agda.TypeChecking.Pretty

import Agda.Utils.Functor (($>))
import Agda.Utils.List

#include "../../undefined.h"
import Agda.Utils.Impossible

-- | Process function clauses into case tree.
--   This involves:
--   1. Coverage checking, generating a split tree.
--   2. Translation of lhs record patterns into rhs uses of projection.
--      Update the split tree.
--   3. Generating a case tree from the split tree.
--   Phases 1. and 2. are skipped if @Nothing@.
compileClauses ::
  Maybe (QName, Type) -- ^ Translate record patterns and coverage check with given type?
  -> [Clause] -> TCM CompiledClauses
compileClauses mt cs = do
  let cls = [(clausePats c, clauseBody c) | c <- cs]
  case mt of
    Nothing -> return $ compile cls
    Just (q, t)  -> do
      splitTree <- coverageCheck q t cs

      reportSDoc "tc.cc" 30 $ sep $ do
        (text "clauses patterns  before compilation") : do
          map (prettyTCM . map unArg . fst) cls
      reportSDoc "tc.cc" 50 $ do
        sep [ text "clauses before compilation"
            , (nest 2 . text . show) cs
            ]
      let cc = compileWithSplitTree splitTree cls
      reportSDoc "tc.cc" 12 $ sep
        [ text "compiled clauses (still containing record splits)"
        , nest 2 $ text (show cc)
        ]
      cc <- translateCompiledClauses cc
      return cc

type Cl  = ([I.Arg Pattern], ClauseBody)
type Cls = [Cl]

compileWithSplitTree :: SplitTree -> Cls -> CompiledClauses
compileWithSplitTree t cs = case t of
  SplitAt i ts ->
    -- the coverage checker does not count dot patterns as variables
    -- in case trees however, they count as variable patterns
    let n = i -- countInDotPatterns i cs
    in  Case n $ compiles ts $ splitOn (length ts == 1) n cs
        -- if there is just one case, we force expansion of catch-alls
        -- this is needed to generate a sound tree on which we can
        -- collapse record pattern splits
  SplittingDone n -> compile cs
    -- after end of split tree, continue with left-to-right strategy

  where

    compiles :: SplitTrees -> Case Cls -> Case CompiledClauses
    compiles ts br@Branches{ conBranches = cons
                           , litBranches = lits
                           , catchAllBranch = Nothing }
      | Map.null lits = emptyBranches { conBranches = updCons cons }
      where
        updCons = Map.mapWithKey $ \ c cl -> case lookup c ts of
                    Nothing -> __IMPOSSIBLE__
                    Just t  -> fmap (compileWithSplitTree t) cl
    compiles ts br    = fmap compile br

    -- increase split index by number of dot patterns we have skipped
    countInDotPatterns :: Int -> [Cl] -> Int
    countInDotPatterns i [] = __IMPOSSIBLE__
    countInDotPatterns i ((ps, _) : _) = i + loop i (map unArg ps) where
      loop 0 ps            = 0
      loop i []            = __IMPOSSIBLE__
      loop i (DotP{} : ps) = 1 + loop i ps
      loop i (_      : ps) = loop (i - 1) ps


compile :: Cls -> CompiledClauses
compile cs = case nextSplit cs of
  Just n  -> Case n $ fmap compile $ splitOn False n cs
  Nothing -> case map (getBody . snd) cs of
    -- It's possible to get more than one clause here due to
    -- catch-all expansion.
    Just t : _  -> Done (map (fmap name) $ fst $ head cs) (shared t)
    Nothing : _ -> Fail
    []          -> __IMPOSSIBLE__
  where
    name (VarP x) = x
    name (DotP _) = underscore
    name ConP{}  = __IMPOSSIBLE__
    name LitP{}  = __IMPOSSIBLE__
    name ProjP{} = __IMPOSSIBLE__

-- | Get the index of the next argument we need to split on.
--   This the number of the first pattern that does a match in the first clause.
nextSplit :: Cls -> Maybe Int
nextSplit []          = __IMPOSSIBLE__
nextSplit ((ps, _):_) = findIndex (not . isVar . unArg) ps

-- | Is this a variable pattern?
isVar :: Pattern -> Bool
isVar VarP{}  = True
isVar DotP{}  = True
isVar ConP{}  = False
isVar LitP{}  = False
isVar ProjP{} = False

-- | @splitOn single n cs@ will force expansion of catch-alls
--   if @single@.
splitOn :: Bool -> Int -> Cls -> Case Cls
splitOn single n cs = mconcat $ map (fmap (:[]) . splitC n) $ expandCatchAlls single n cs

splitC :: Int -> Cl -> Case Cl
splitC n (ps, b) = case unArg p of
  ProjP d     -> conCase d $ WithArity 0 (ps0 ++ ps1, b)
  ConP c _ qs -> conCase (conName c) $ WithArity (length qs) (ps0 ++ map (fmap namedThing) qs ++ ps1, b)
  LitP l      -> litCase l (ps0 ++ ps1, b)
  VarP{}      -> catchAll (ps, b)
  DotP{}      -> catchAll (ps, b)
  where
    (ps0, p, ps1) = extractNthElement' n ps

-- | Expand catch-alls that appear before actual matches.
--
-- Example:
--
-- @
--    true  y
--    x     false
--    false y
-- @
--
-- will expand the catch-all @x@ to @false@.
--
-- Catch-alls need also to be expanded if
-- they come before/after a record pattern, otherwise we get into
-- trouble when we want to eliminate splits on records later.
--
expandCatchAlls :: Bool -> Int -> Cls -> Cls
expandCatchAlls single n cs =
  -- Andreas, 2013-03-22
  -- if there is a single case (such as for record splits)
  -- we force expansion
  if single then doExpand =<< cs else
  case cs of
  _            | all (isCatchAllNth . fst) cs -> cs
  (ps, b) : cs | not (isCatchAllNth ps) -> (ps, b) : expandCatchAlls False n cs
               | otherwise -> map (expand ps b) expansions ++ (ps, b) : expandCatchAlls False n cs
  _ -> __IMPOSSIBLE__
  where
    -- In case there is only one branch in the split tree, we expand all
    -- catch-alls for this position
    -- The @expansions@ are collected from all the clauses @cs@ then.
    -- Note: @expansions@ could be empty, so we keep the orignal clause.
    doExpand c@(ps, b)
      | isVar $ unArg $ nth ps = map (expand ps b) expansions ++ [c]
      | otherwise              = [c]

    -- True if nth pattern is variable or there are less than n patterns.
    isCatchAllNth ps = all (isVar . unArg) $ take 1 $ drop n ps

    nth qs = headDef __IMPOSSIBLE__ $ drop n qs

    classify (LitP l)     = Left l
    classify (ConP c _ _) = Right c
    classify _            = __IMPOSSIBLE__

    -- All non-catch-all patterns following this one (at position n).
    -- These are the cases the wildcard needs to be expanded into.
    expansions = nubBy ((==) `on` (classify . unArg))
               . filter (not . isVar . unArg)
               . map (nth . fst)
               $ cs

    expand ps b q =
      case unArg q of
        ConP c mt qs' -> (ps0 ++ [q $> ConP c mt conPArgs] ++ ps1,
                         substBody n' m (Con c conArgs) b)
          where
            m        = length qs'
            -- replace all direct subpatterns of q by _
            conPArgs = map (fmap ($> VarP underscore)) qs'
            conArgs  = zipWith (\ q n -> q $> var n) qs' $ downFrom m
        LitP l -> (ps0 ++ [q $> LitP l] ++ ps1, substBody n' 0 (Lit l) b)
        _ -> __IMPOSSIBLE__
      where
        (ps0, rest) = splitAt n ps
        ps1         = maybe __IMPOSSIBLE__ snd $ uncons rest

        n' = countVars ps0
        countVars = sum . map (count . unArg)
        count VarP{}        = 1
        count (ConP _ _ ps) = countVars $ map (fmap namedThing) ps
        count DotP{}        = 1   -- dot patterns are treated as variables in the clauses
        count _             = 0

substBody :: Int -> Int -> Term -> ClauseBody -> ClauseBody
substBody _ _ _ NoBody = NoBody
substBody 0 m v b = case b of
  Bind   b -> foldr (.) id (replicate m (Bind . Abs underscore)) $ subst v (absBody $ raise m b)
  _        -> __IMPOSSIBLE__
substBody n m v b = case b of
  Bind b   -> Bind $ fmap (substBody (n - 1) m v) b
  _        -> __IMPOSSIBLE__
