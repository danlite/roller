module Registry exposing (FindErr(..), FindResult, Registry, findTable, map)

import Dice exposing (RegisteredRollable, ResolvedBundle)
import Dict exposing (Dict)
import Result exposing (andThen, fromMaybe)


type alias Registry =
    Dict String RegisteredRollable


type Finder a
    = Finder (Registry -> FindResult a)


type FindErr
    = NotFound String


type alias FindResult a =
    Result FindErr a


fail : FindErr -> Finder a
fail err =
    Finder (\_ -> Err err)


findTable : String -> Finder RegisteredRollable
findTable path =
    Finder (\reg -> fromMaybe (NotFound path) (Dict.get path reg))


map : (a -> b) -> Finder a -> Finder b
map func (Finder finA) =
    Finder
        (\registry ->
            finA registry
                |> andThen (\a -> Ok (func a))
        )



{- Contrived example for using map -}
-- findPath : String -> Finder String
-- findPath string =
-- map .path (findTable string)
--
-- look : (a -> msg) -> Finder a -> Cmd msg
-- look tagger finder =
--     command (Find (map tagger finder))
-- type MyCmd msg
--     = Find (Finder msg)
