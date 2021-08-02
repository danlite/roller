module V2.Rollable exposing (..)

import Dice exposing (Expr, FormulaTerm(..), Range)
import Dict exposing (Dict)
import List.Extra
import Maybe exposing (withDefault)
import Result exposing (fromMaybe)


type DiceError
    = MissingContextVariable String
    | ValueNotMatchingRow Int


type alias IndexPath =
    List Int


type RollableValue
    = RollableValue { var : String, expression : Expr }
    | RolledValue { var : String, expression : Expr, value : Int }


type RollableText
    = PlainText String
    | RollableText RollableValue


type alias Row =
    { text : String, range : Range, refs : List RollableRef }


type alias EvaluatedRow =
    { text : List RollableText, refs : List RollableRef }


type alias RollInstructions =
    { title : Maybe String
    , rollCount : Maybe Variable
    , total : Maybe Variable
    , dice : Maybe Expr
    , unique : Bool
    , ignore : List Variable
    , modifier : Maybe Variable

    --   store?: {
    --     [key: string]: '$roll'
    --   }
    }


type alias RollableRefData =
    { path : String, instructions : RollInstructions, title : Maybe String }


type alias WithBundle a =
    { a | bundle : Bundle }


type alias WithTableResult a =
    { a | result : List TableRollResult, title : String }


type RollableRef
    = Ref RollableRefData
    | BundleRef (WithBundle RollableRefData)
    | RolledTable (WithTableResult RollableRefData)


type TableRollResult
    = RolledRow { result : EvaluatedRow, rollTotal : Int }
    | MissingRowError { rollTotal : Int }


type alias TableSource =
    { rows : List Row
    , inputs : List RollableRef
    , path : String
    , title : String
    }


type alias Bundle =
    { path : String, title : String, tables : List RollableRef }


type Rollable
    = RollableTable TableSource
    | RollableBundle Bundle
    | MissingRollableError { path : String }


type alias Model =
    List RollableRef


type alias Registry =
    Dict String Rollable


aRegistry : Registry
aRegistry =
    Dict.empty


findTableSource : Registry -> String -> Maybe TableSource
findTableSource registry path =
    case Dict.get path registry of
        Just (RollableTable data) ->
            Just data

        _ ->
            Nothing


findBundleSource : Registry -> String -> Maybe Bundle
findBundleSource registry path =
    case Dict.get path registry of
        Just (RollableBundle data) ->
            Just data

        _ ->
            Nothing


rollResultForRollOnTable : List Row -> Int -> TableRollResult
rollResultForRollOnTable rows rollTotal =
    case List.Extra.getAt (rollTotal - 1) rows of
        Just row ->
            RolledRow { result = EvaluatedRow [] row.refs, rollTotal = rollTotal }

        _ ->
            MissingRowError { rollTotal = rollTotal }


tableRollResultRefs : TableRollResult -> List RollableRef
tableRollResultRefs result =
    case result of
        RolledRow r ->
            r.result.refs

        _ ->
            []


refAtIndex : IndexPath -> List RollableRef -> Maybe RollableRef
refAtIndex index model =
    case index of
        [] ->
            Nothing

        [ i ] ->
            List.Extra.getAt i model

        i :: rest ->
            case List.Extra.getAt i model of
                Just (BundleRef bundleRef) ->
                    refAtIndex rest bundleRef.bundle.tables

                Just (RolledTable info) ->
                    case info.result of
                        [ rollResult ] ->
                            case rollResult of
                                RolledRow rolledRow ->
                                    refAtIndex rest rolledRow.result.refs

                                _ ->
                                    Nothing

                        _ ->
                            Nothing

                _ ->
                    Nothing


tableMin : TableSource -> Maybe Int
tableMin table =
    List.minimum (List.map (\r -> r.range.min) table.rows)


tableMax : TableSource -> Maybe Int
tableMax table =
    List.maximum (List.map (\r -> r.range.max) table.rows)


tableSize : TableSource -> Int
tableSize table =
    case tableMax table of
        Nothing ->
            0

        Just max ->
            case tableMin table of
                Nothing ->
                    0

                Just min ->
                    max - min


dieForTable : TableSource -> FormulaTerm
dieForTable table =
    MultiDie { count = 1, sides = tableSize table }


type Variable
    = ConstValue Int
    | ContextKey String


type alias RollContext =
    Dict String Int


type alias ContextVariableResult =
    Result DiceError Int


valueInContext : Variable -> RollContext -> ContextVariableResult
valueInContext var context =
    case var of
        ConstValue n ->
            Ok n

        ContextKey k ->
            fromMaybe (MissingContextVariable k) (Dict.get k context)


rollCount : Maybe Variable -> RollContext -> ContextVariableResult
rollCount var context =
    withDefault
        (Ok 1)
        (Maybe.map (\v -> valueInContext v context) var)
