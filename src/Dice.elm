module Dice exposing (..)

import List exposing (map)
import String exposing (fromInt)


type alias Die =
    { sides : Int }


type FormulaTerm
    = Constant Int
    | MultiDie
        { count : Int
        , sides : Int
        }


formulaTermString : FormulaTerm -> String
formulaTermString term =
    case term of
        Constant c ->
            fromInt c

        MultiDie m ->
            fromInt m.count ++ "d" ++ fromInt m.sides


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



-- rollTableRef : RollContext -> ResolvedTableRef -> Result DiceError TableRefRoller
-- rollTableRef context tableRef =
--     rollTableRefTables
--         context
--         tableRef
--         |> Result.andThen
--             (Random.map
--                 (\rolledTables -> RolledTableRef tableRef rolledTables)
--                 >> Ok
--             )
-- rollTableRefTables : RollContext -> ResolvedTableRef -> Result DiceError (Random.Generator (List RolledTable))
-- rollTableRefTables context tableRef =
--     rollCount tableRef.ref.rollCount context
--         |> Result.andThen
--             (\count ->
--                 Ok
--                     (Random.list
--                         count
--                         (rollTable tableRef.table tableRef.table.dice)
--                     )
--             )
-- rollBundleTables : RollContext -> ResolvedBundle -> Result DiceError (Random.Generator (List RolledTableRef))
-- rollBundleTables context bundle =
--     Result.Extra.combine
--         (List.map
--             (rollTableRef context)
--             bundle.tables
--         )
--         |> Result.andThen
--             (Random.Extra.combine >> Ok)


type Expr
    = Term FormulaTerm
    | Add Expr Expr
    | Sub Expr Expr
