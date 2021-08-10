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


type Expr
    = Term FormulaTerm
    | Add Expr Expr
    | Sub Expr Expr


type alias RollableValue =
    { var : String, expression : Expr, value : RolledValue }


type RolledValue
    = UnrolledValue
    | ErrorValue
    | ValueResult Int


type RowTextComponent
    = PlainText String
    | RollableText RollableValue


formulaTermString : FormulaTerm -> String
formulaTermString term =
    case term of
        Constant c ->
            fromInt c

        MultiDie m ->
            fromInt m.count ++ "d" ++ fromInt m.sides


type alias Range =
    { min : Int, max : Int }


rangeMembers : Range -> List Int
rangeMembers range =
    List.range range.min range.max


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
