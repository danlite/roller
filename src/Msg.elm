module Msg exposing (InputField(..), Msg(..), Roll(..), RollResultIndex, RollableLoadResult)

import Debounce
import Dice exposing (DiceError, RegisteredRollable, RolledFormulaTerm, RolledRollable, RolledRollableResult)
import Http
import KeyPress exposing (KeyValue)
import Yaml.Decode


type InputField
    = Count
    | Sides
    | Dice


type alias RollResultIndex =
    List Int


type Roll
    = SelectedTable
    | Reroll RollResultIndex


type alias RollableLoadResult =
    Result Http.Error (Result Yaml.Decode.Error RegisteredRollable)


type Msg
    = Roll Roll
    | NewResults RolledFormulaTerm
    | NewRolledTable RolledRollableResult
    | RerolledTable RollResultIndex RolledRollableResult
    | Change InputField String
    | GotDirectory (Result Http.Error (List String))
    | LoadTable String
    | LoadedTable String RollableLoadResult
    | InputTableSearch String
    | StartTableSearch String
    | DebounceMsg Debounce.Msg
    | KeyPressTableSearch KeyValue
    | TableSearchFocus Bool
