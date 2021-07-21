module Msg exposing (InputField(..), Msg(..), TableLoadResult)

import Debounce
import Dice exposing (RolledFormulaTerm, RolledTable, Table)
import Http
import KeyPress exposing (KeyValue)
import Yaml.Decode


type InputField
    = Count
    | Sides
    | Dice


type alias TableLoadResult =
    Result Http.Error (Result Yaml.Decode.Error Table)


type Msg
    = Roll
    | NewResults RolledFormulaTerm
    | NewRolledTable RolledTable
    | Change InputField String
    | GotDirectory (Result Http.Error (List String))
    | LoadTable String
    | LoadedTable String TableLoadResult
    | InputTableSearch String
    | StartTableSearch String
    | DebounceMsg Debounce.Msg
    | KeyPressTableSearch KeyValue
    | TableSearchFocus Bool
