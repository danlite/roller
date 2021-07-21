module Msg exposing (InputField(..), Msg(..), RollableLoadResult)

import Debounce
import Dice exposing (RegisteredRollable, RolledFormulaTerm, RolledTable)
import Http
import KeyPress exposing (KeyValue)
import Yaml.Decode


type InputField
    = Count
    | Sides
    | Dice


type alias RollableLoadResult =
    Result Http.Error (Result Yaml.Decode.Error RegisteredRollable)


type Msg
    = Roll
    | NewResults RolledFormulaTerm
    | NewRolledTable RolledTable
    | Change InputField String
    | GotDirectory (Result Http.Error (List String))
    | LoadTable String
    | LoadedTable String RollableLoadResult
    | InputTableSearch String
    | StartTableSearch String
    | DebounceMsg Debounce.Msg
    | KeyPressTableSearch KeyValue
    | TableSearchFocus Bool
