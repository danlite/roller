module Registry exposing (FindErr(..), FindResult, Registry, findTable, map)

import Dict exposing (Dict)
import Result exposing (andThen, fromMaybe)
import Rollable exposing (Rollable)


type alias Registry =
    Dict String Rollable


type Finder a
    = Finder (Registry -> FindResult a)


type FindErr
    = NotFound String


type alias FindResult a =
    Result FindErr a


findTable : String -> Finder Rollable
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
