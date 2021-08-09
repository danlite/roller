module Roll exposing (..)

import Dice exposing (Die, Expr(..), FormulaTerm(..), rangeMembers)
import List exposing (sum)
import List.Extra
import Maybe exposing (withDefault)
import Random exposing (Generator, andThen, map)
import Random.Extra exposing (sequence)
import Rollable
    exposing
        ( Bundle
        , Registry
        , RollInstructions
        , RollableRef(..)
        , Row
        , TableRollResult(..)
        , TableSource
        , Variable(..)
        , WithTableResult
        , findBundleSource
        , findTableSource
        , pathString
        , rollResultForRollOnTable
        , updateBundle
        )


pickRowFromTable : List Row -> Generator TableRollResult
pickRowFromTable rows =
    Random.map (rollResultForRollOnTable rows) (Random.int 1 (List.length rows))


evaluateVariable : a -> Variable -> Int
evaluateVariable _ variable =
    case variable of
        ConstValue v ->
            v

        ContextKey k ->
            Debug.todo ("evaluate context key: " ++ k)


rollResultNumber : TableRollResult -> Int
rollResultNumber res =
    case res of
        RolledRow r ->
            r.rollTotal

        MissingRowError err ->
            err.rollTotal


siblingResultNumbers : TableRollResult -> List Int
siblingResultNumbers res =
    case res of
        RolledRow r ->
            rangeMembers r.range

        MissingRowError err ->
            [ err.rollTotal ]


rollOnTable : TableSource -> RollInstructions -> Generator (List TableRollResult)
rollOnTable source instructions =
    let
        rollCount =
            evaluateVariable {} (withDefault (ConstValue 1) instructions.rollCount)

        doRoll =
            rollSingleRowOnTable source
    in
    doRoll instructions
        |> andThen
            (\r ->
                if rollCount == 1 then
                    Random.constant r
                        |> List.singleton
                        |> sequence

                else
                    let
                        modifiedInstructions =
                            { instructions
                                | rollCount = Just (ConstValue (rollCount - 1))
                                , ignore =
                                    if instructions.unique then
                                        instructions.ignore ++ (siblingResultNumbers r |> List.map ConstValue)

                                    else
                                        instructions.ignore
                            }
                    in
                    Random.constant r
                        :: (doRoll (Debug.log "modifiedInstructions" modifiedInstructions) |> List.singleton)
                        |> sequence
            )


rollSingleRowOnTable : TableSource -> RollInstructions -> Generator TableRollResult
rollSingleRowOnTable source instructions =
    let
        dice =
            instructions.dice |> withDefault source.dice

        ignore =
            instructions.ignore |> List.map (evaluateVariable {})
    in
    rollExpr dice
        |> map evaluateExpr
        |> map (rollResultForRollOnTable source.rows)
        |> andThen
            (\r ->
                let
                    rollNumber =
                        rollResultNumber r
                in
                if List.member (Debug.log "rollNumber" rollNumber) ignore then
                    rollSingleRowOnTable source instructions

                else
                    Random.constant r
            )


rollOnBundle : Registry -> Bundle -> Generator Bundle
rollOnBundle registry bundle =
    List.map (rollOnRef registry) bundle.tables
        |> Random.Extra.sequence
        |> Random.map (\refs -> { bundle | tables = refs })


otherwiseMaybe : Maybe a -> Maybe a -> Maybe a
otherwiseMaybe value fallback =
    case value of
        Nothing ->
            fallback

        _ ->
            value


rollOnRef : Registry -> RollableRef -> Generator RollableRef
rollOnRef registry r =
    case r of
        Ref ref ->
            case findTableSource registry ref.path of
                Just table ->
                    rollOnTable table ref.instructions
                        |> Random.map
                            (\res ->
                                RolledTable
                                    { path = ref.path
                                    , instructions = ref.instructions
                                    , result = res
                                    , title = ref.instructions.title |> withDefault table.title
                                    }
                            )

                _ ->
                    case findBundleSource registry ref.path of
                        Just bundle ->
                            rollOnBundle registry bundle
                                |> Random.map
                                    (\res ->
                                        BundleRef
                                            { bundle = res
                                            , instructions = ref.instructions
                                            , path = ref.path
                                            , title = ref.instructions.title |> otherwiseMaybe ref.title
                                            }
                                    )

                        _ ->
                            Debug.todo ("unfindable table/bundle in registry: " ++ pathString ref.path)

        BundleRef ref ->
            rollOnBundle registry (Debug.log "bundle" ref.bundle)
                |> Random.map (updateBundle ref)

        RolledTable ref ->
            rollOnRef registry (Ref { path = ref.path, instructions = ref.instructions, title = Just ref.title })


onlyOneRollCount : RollInstructions -> RollInstructions
onlyOneRollCount instructions =
    { instructions | rollCount = Just (ConstValue 1) }


updateRowResult : Int -> TableRollResult -> WithTableResult a -> WithTableResult a
updateRowResult rowIndex newResult rolledTable =
    { rolledTable | result = List.Extra.setAt rowIndex newResult rolledTable.result }


rerollSingleTableRow : Registry -> RollableRef -> Int -> Generator RollableRef
rerollSingleTableRow registry r rowIndex =
    case r of
        RolledTable ref ->
            case findTableSource registry ref.path of
                Just table ->
                    let
                        newRowRoll =
                            -- TODO: modify instructions for "ignore" using existing table context
                            rollOnTable table (onlyOneRollCount ref.instructions)
                    in
                    newRowRoll
                        |> Random.map
                            (List.head
                                >> Maybe.map
                                    (\rollResult ->
                                        updateRowResult rowIndex rollResult ref |> RolledTable
                                    )
                                >> Maybe.withDefault r
                            )

                _ ->
                    Random.constant r

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
