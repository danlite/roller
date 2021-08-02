module V2.Random exposing (..)

import Dice exposing (Die, Expr(..), FormulaTerm(..))
import List exposing (sum)
import Random exposing (Generator)
import Random.Extra
import V2.Rollable
    exposing
        ( Bundle
        , RollInstructions
        , RollableRef(..)
        , Row
        , TableRollResult
        , TableSource
        , aRegistry
        , findTableSource
        , rollResultForRollOnTable
        )


pickRowFromTable : List Row -> Generator TableRollResult
pickRowFromTable rows =
    Random.map (rollResultForRollOnTable rows) (Random.int 1 (List.length rows))


rollOnTable : RollInstructions -> TableSource -> Generator TableRollResult
rollOnTable _ source =
    -- TODO: obey instructions for rollCount > 1 (TBD: row ranges, reroll, unique)
    pickRowFromTable source.rows


rollOnBundle : Bundle -> Generator Bundle
rollOnBundle bundle =
    List.map rollOnRef bundle.tables
        |> Random.Extra.sequence
        |> Random.map (\refs -> { bundle | tables = refs })


rollOnRef : RollableRef -> Generator RollableRef
rollOnRef r =
    case r of
        Ref ref ->
            case findTableSource aRegistry ref.path of
                Just table ->
                    -- TODO: multiple rolls on table
                    rollOnTable ref.instructions table
                        |> Random.map List.singleton
                        |> Random.map
                            (\res ->
                                RolledTable
                                    { path = ref.path
                                    , instructions = ref.instructions
                                    , result = res
                                    , title = table.title
                                    }
                            )

                _ ->
                    Random.constant r

        BundleRef ref ->
            rollOnBundle ref.bundle
                |> Random.map
                    (\res ->
                        BundleRef
                            { ref
                                | bundle = res
                            }
                    )

        _ ->
            Random.constant r


type alias ExprRoller =
    Random.Generator RolledExpr


rollFormulaTerm : FormulaTerm -> FormulaTermRoller
rollFormulaTerm term =
    case term of
        Constant c ->
            rollConstant c

        MultiDie m ->
            rollMultiDie m


rollExpr : Expr -> ExprRoller
rollExpr expr =
    case expr of
        Term term ->
            Random.map RolledTerm (rollFormulaTerm term)

        Add e1 e2 ->
            Random.map2 RolledAdd (rollExpr e1) (rollExpr e2)

        Sub e1 e2 ->
            Random.map2 RolledSub (rollExpr e1) (rollExpr e2)


type alias RolledConstant =
    Int


rollConstant : Int -> FormulaTermRoller
rollConstant constant =
    Random.map RolledConstant (Random.constant constant)


type RolledFormulaTerm
    = RolledConstant RolledConstant
    | RolledMultiDie RolledMultiDie


type alias FormulaTermRoller =
    Random.Generator RolledFormulaTerm


valueOf : RolledFormulaTerm -> Int
valueOf term =
    case term of
        RolledConstant c ->
            c

        RolledMultiDie m ->
            sum (List.map .side m)


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
    { count : Int, sides : Int }
    -> FormulaTermRoller
rollMultiDie multiDie =
    Random.map RolledMultiDie (Random.list multiDie.count (rollDie (Die multiDie.sides)))


type RolledExpr
    = RolledTerm RolledFormulaTerm
    | RolledAdd RolledExpr RolledExpr
    | RolledSub RolledExpr RolledExpr


evaluateExpr : RolledExpr -> Int
evaluateExpr expr =
    case expr of
        RolledTerm term ->
            valueOf term

        RolledAdd e1 e2 ->
            evaluateExpr e1 + evaluateExpr e2

        RolledSub e1 e2 ->
            evaluateExpr e1 - evaluateExpr e2
