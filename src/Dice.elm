module Dice exposing (..)

import Dict exposing (Dict)
import List exposing (map, sum)
import List.Extra
import Maybe exposing (withDefault)
import Random
import Random.Extra
import Result exposing (fromMaybe)
import Result.Extra
import String exposing (fromInt)


type DiceError
    = MissingContextVariable String
    | ValueNotMatchingRow Int


type alias Die =
    { sides : Int }


type alias RolledDie =
    { side : Int }


type alias DieRoller =
    Random.Generator RolledDie


rollDie : Die -> DieRoller
rollDie die =
    Random.map RolledDie (Random.int 1 die.sides)


type alias RolledMultiDie =
    List RolledDie


type alias MultiDieRoller =
    Random.Generator RolledMultiDie


rollMultiDie :
    { count : Int
    , sides : Int
    }
    -> FormulaTermRoller
rollMultiDie multiDie =
    Random.map RolledMultiDie (Random.list multiDie.count (rollDie (Die multiDie.sides)))


type alias RolledConstant =
    Int


rollConstant : Int -> FormulaTermRoller
rollConstant constant =
    Random.map RolledConstant (Random.constant constant)


type FormulaTerm
    = Constant Int
    | MultiDie
        { count : Int
        , sides : Int
        }


type RolledFormulaTerm
    = RolledConstant RolledConstant
    | RolledMultiDie RolledMultiDie


type alias FormulaTermRoller =
    Random.Generator RolledFormulaTerm


rollFormulaTerm : FormulaTerm -> FormulaTermRoller
rollFormulaTerm term =
    case term of
        Constant c ->
            rollConstant c

        MultiDie m ->
            rollMultiDie m


formulaTermString : FormulaTerm -> String
formulaTermString term =
    case term of
        Constant c ->
            fromInt c

        MultiDie m ->
            fromInt m.count ++ "d" ++ fromInt m.sides


evaluateExpr : RolledExpr -> Int
evaluateExpr expr =
    case expr of
        RolledTerm term ->
            valueOf term

        RolledAdd e1 e2 ->
            evaluateExpr e1 + evaluateExpr e2

        RolledSub e1 e2 ->
            evaluateExpr e1 - evaluateExpr e2


valueOf : RolledFormulaTerm -> Int
valueOf term =
    case term of
        RolledConstant c ->
            c

        RolledMultiDie m ->
            sum (List.map .side m)


type alias Range =
    { min : Int, max : Int }


rangeIncludes : Int -> Range -> Bool
rangeIncludes val range =
    val >= range.min && val <= range.max


makeRange : Int -> Int -> Result String Range
makeRange n1 n2 =
    if n1 > n2 then
        Err ("Second argument (" ++ fromInt n2 ++ ") must be greater than or equal to the first argument (" ++ fromInt n1 ++ ")")

    else
        Ok (Range n1 n2)


makeSingleRange : Int -> Range
makeSingleRange n =
    Range n n


rangeString : Range -> String
rangeString range =
    if range.min == range.max then
        fromInt range.min

    else
        String.join "–" (map fromInt [ range.min, range.max ])


type alias Row =
    { range : Range, content : String, tableRefs : List TableRef }


type alias Table =
    { rows : List Row, title : String, dice : Expr }


type alias Bundle =
    { tables : List TableRef, title : String }


type alias ResolvedBundle =
    { tables : List ResolvedTableRef, title : String }


type Rollable
    = RollableTable Table
    | RollableBundle Bundle


type alias RegisteredRollable =
    { path : String, rollable : Rollable }


type Variable
    = ConstValue Int
    | ContextKey String


type alias TableRef =
    { path : String
    , title : Maybe String
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


type alias ResolvedTableRef =
    { table : Table, ref : TableRef }


tableMin : Table -> Maybe Int
tableMin table =
    List.minimum (List.map (\r -> r.range.min) table.rows)


tableMax : Table -> Maybe Int
tableMax table =
    List.maximum (List.map (\r -> r.range.max) table.rows)


tableSize : Table -> Int
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


dieForTable : Table -> FormulaTerm
dieForTable table =
    MultiDie { count = 1, sides = tableSize table }


type alias RolledTable =
    { roll : RolledExpr, row : TableRowRollResult, table : Table }


type alias RolledBundle =
    { tables : List RolledTableRef, bundle : ResolvedBundle }


type RolledRollable
    = RolledBundle_ RolledBundle
    | RolledTable_ RolledTable


type alias RolledTableRef =
    { ref : ResolvedTableRef, rolled : List RolledTable }


type alias RolledRollableResult =
    Result DiceError RolledRollable


type alias RollableRoller =
    Random.Generator RolledRollableResult


type alias BundleRoller =
    Random.Generator RolledBundle


type alias TableRoller =
    Random.Generator RolledTable


type alias TableRefRoller =
    Random.Generator RolledTableRef


type alias TableRowRollResult =
    Result DiceError Row


tableRowForRoll : RolledExpr -> Table -> TableRowRollResult
tableRowForRoll roll table =
    let
        rollValue =
            evaluateExpr roll
    in
    case List.Extra.find (\r -> rangeIncludes rollValue r.range) table.rows of
        Nothing ->
            Err (ValueNotMatchingRow rollValue)

        Just row ->
            Ok row


rollTable : Table -> Expr -> TableRoller
rollTable table expr =
    Random.map (\r -> { roll = r, row = tableRowForRoll r table, table = table }) (rollExpr expr)


rollBundle : RollContext -> ResolvedBundle -> Result DiceError BundleRoller
rollBundle context bundle =
    rollBundleTables context bundle
        |> Result.andThen
            (Random.map
                (\tableRolls -> { tables = tableRolls, bundle = bundle })
                >> Ok
            )


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


rollTableRef : RollContext -> ResolvedTableRef -> Result DiceError TableRefRoller
rollTableRef context tableRef =
    rollTableRefTables
        context
        tableRef
        |> Result.andThen
            (Random.map
                (\rolledTables -> RolledTableRef tableRef rolledTables)
                >> Ok
            )


rollTableRefTables : RollContext -> ResolvedTableRef -> Result DiceError (Random.Generator (List RolledTable))
rollTableRefTables context tableRef =
    rollCount tableRef.ref.rollCount context
        |> Result.andThen
            (\count ->
                Ok
                    (Random.list
                        count
                        (rollTable tableRef.table tableRef.table.dice)
                    )
            )


rollBundleTables : RollContext -> ResolvedBundle -> Result DiceError (Random.Generator (List RolledTableRef))
rollBundleTables context bundle =
    Result.Extra.combine
        (List.map
            (rollTableRef context)
            bundle.tables
        )
        |> Result.andThen
            (Random.Extra.combine >> Ok)


type Expr
    = Term FormulaTerm
    | Add Expr Expr
    | Sub Expr Expr


type RolledExpr
    = RolledTerm RolledFormulaTerm
    | RolledAdd RolledExpr RolledExpr
    | RolledSub RolledExpr RolledExpr


type alias ExprRoller =
    Random.Generator RolledExpr


rollExpr : Expr -> ExprRoller
rollExpr expr =
    case expr of
        Term term ->
            Random.map RolledTerm (rollFormulaTerm term)

        Add e1 e2 ->
            Random.map2 RolledAdd (rollExpr e1) (rollExpr e2)

        Sub e1 e2 ->
            Random.map2 RolledSub (rollExpr e1) (rollExpr e2)
