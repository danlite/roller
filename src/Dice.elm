module Dice exposing (..)

import List exposing (map, sum)
import List.Extra
import Random
import String exposing (fromInt)


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
    { path : String, rows : List Row, title : String, dice : Expr }


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
    { roll : RolledExpr, row : TableRowRollResult }


type alias TableRoller =
    Random.Generator RolledTable


type alias ValueNotMatchingRow =
    Int


type alias TableRowRollResult =
    Result ValueNotMatchingRow Row


tableRowForRoll : RolledExpr -> Table -> TableRowRollResult
tableRowForRoll roll table =
    let
        rollValue =
            evaluateExpr roll
    in
    case List.Extra.find (\r -> rangeIncludes rollValue r.range) table.rows of
        Nothing ->
            Err rollValue

        Just row ->
            Ok row


rollTable : Table -> Expr -> TableRoller
rollTable table expr =
    Random.map (\r -> { roll = r, row = tableRowForRoll r table }) (rollExpr expr)


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
