-- Encode monomorphic types during pruning.
{-# LANGUAGE TypeFamilies, RecordWildCards #-}
module QuickSpec.Pruning.EncodeTypes where

import Twee.Base
import QuickSpec.Pruning
import qualified QuickSpec.Term as QS
import QuickSpec.Type
import QuickSpec.Prop
import qualified Data.Set as Set
import Data.Set(Set)
import Data.List

data Tagged f =
    Func f
  | Tag Type
  deriving (Eq, Ord, Show, Typeable)

type TypedTerm f = QS.Term f
type UntypedTerm f = Term (Tagged f)

data State f =
  State {
    st_pruner :: Pruner (UntypedTerm f),
    st_functions :: Set (Tagged f) }

encodeMonoTypes :: (Ord f, Typeable f, Typed f) =>
  Pruner (UntypedTerm f) -> Pruner (TypedTerm f)
encodeMonoTypes pruner =
  makePruner normaliseMono addMono
    State {
      st_pruner = pruner,
      st_functions = Set.empty }

normaliseMono :: (Ord f, Typed f, Typeable f) =>
  State f -> TypedTerm f -> TypedTerm f
normaliseMono State{..} =
  -- Note that we don't call addFunction on the functions in the term.
  -- This is because doing so might be expensive, as adding typing
  -- axioms starts the completion algorithm.
  -- This is OK because in encode, we tag all functions and variables
  -- with their types (i.e. we can fall back to the naive type encoding).
  decode . normalise st_pruner . encode

addMono :: (Ord f, Typed f, Typeable f) =>
  Prop (TypedTerm f) -> State f -> State f
addMono prop state =
  State{
    st_pruner = add st_pruner (fmap encode prop),
    st_functions = st_functions }
  where
    State{..} =
      foldl' addFunction state (map QS.fun_value (QS.funs prop))

addFunction :: (Ord f, Typed f, Typeable f) =>
  State f -> f -> State f
addFunction st@State{..} f
  | Func f `Set.member` st_functions = st
  | otherwise =
    State{
      st_pruner = foldl' add st_pruner (concatMap typingAxioms funcs),
      st_functions = Set.union st_functions (Set.fromList funcs) }
    where
      funcs = Func f:tags
      tags =
        Set.toList $
          Set.fromList (map Tag (typeRes (typ f):typeArgs (typ f)))
          Set.\\ st_functions

-- Compute the typing axioms for a function or type tag.
typingAxioms :: (Ord f, Typed f, Typeable f) =>
  Tagged f -> [Prop (UntypedTerm f)]
typingAxioms (Tag ty) =
  [build (tag ty (tag ty x)) === build (tag ty x)]
  where
    x = var (V 0)
typingAxioms (Func func) =
  [build (tag res t) === t] ++
  [tagArg i ty === t | (i, ty) <- zip [0..] args]
  where
    f = fun (Func func)
    xs = take n (map (var . V) [0..])

    ty = typ func
    n = typeArity ty
    args = typeArgs ty
    res = typeRes ty

    t = build (app f xs)

    tagArg i ty =
      build $ app f $
        take i xs ++
        [tag ty (xs !! i)] ++
        drop (i+1) xs

tag :: (Ord f, Typed f, Typeable f, Build a, BuildFun a ~ Tagged f) =>
  Type -> a -> Builder (Tagged f)
tag ty t = app (fun (Tag ty)) t

encode :: (Ord f, Typed f, Typeable f) =>
  TypedTerm f -> UntypedTerm f
encode = build . enc
  where
    -- We always add type tags; see comment in normaliseMono.
    -- In the common case, twee will immediately remove these surplus type tags
    -- by rewriting using the typing axioms.
    enc (QS.Var (QS.V ty n)) = tag ty (var (V n))
    enc (QS.App (QS.F f) ts) =
      tag (typeRes (typ f)) (app (fun (Func f)) (map enc (unpack ts)))

decode :: (Ord f, Typed f, Typeable f) =>
  UntypedTerm f -> TypedTerm f
decode = build . dec
  where
    dec (App (F (Tag ty)) (Cons (Var (V x)) Empty)) =
      QS.var (QS.V ty x)
    dec (App (F Tag{}) (Cons t Empty)) = dec t
    dec (App (F Tag{}) _) =
      error "Tag function applied with wrong arity"
    dec (App (F (Func f)) ts) =
      QS.app (QS.fun f) (map dec (unpack ts))
    dec (Var _) =
      error "Naked variable in type-encoded term"