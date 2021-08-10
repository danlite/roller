module Roll exposing (..)

import Dice exposing (Die, Expr(..), FormulaTerm(..), RollableValue, RolledValue(..), RowTextComponent(..), rangeMembers)
import Dict
import List exposing (sum)
import List.Extra
import Maybe exposing (withDefault)
import Random exposing (..)
import Random.Extra exposing (sequence)
import RollContext exposing (Context, addToContextFromRef, addToContextFromResults)
import Rollable
    exposing
        ( Bundle
        , EvaluatedRow
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


evaluateVariable : Context -> Variable -> Int
evaluateVariable context variable =
    case variable of
        ConstValue v ->
            v

        ContextKey k ->
            case Dict.get k context of
                Just v ->
                    v

                _ ->
                    Debug.todo ("missing context key: " ++ k)


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


rollOnTable : TableSource -> Context -> RollInstructions -> Generator (List TableRollResult)
rollOnTable source context instructions =
    let
        rollCount =
            evaluateVariable context (withDefault (ConstValue 1) instructions.rollCount)

        doRoll =
            rollSingleRowOnTable context source
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
                    map2 (::)
                        (Random.constant r)
                        (rollOnTable source context modifiedInstructions)
            )


rollSingleRowOnTable : Context -> TableSource -> RollInstructions -> Generator TableRollResult
rollSingleRowOnTable context source instructions =
    let
        dice =
            instructions.dice |> withDefault source.dice

        ignore =
            instructions.ignore |> List.map (evaluateVariable context)
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
                if List.member rollNumber ignore then
                    rollSingleRowOnTable context source instructions

                else
                    evaluateRollResult r
            )


evaluateRollResult : TableRollResult -> Generator TableRollResult
evaluateRollResult result =
    case result of
        RolledRow r ->
            map (\e -> RolledRow { r | result = e }) (evaluateRowText r.result)

        _ ->
            constant result


evaluateRowText : EvaluatedRow -> Generator EvaluatedRow
evaluateRowText row =
    List.map rollText row.text
        |> sequence
        |> map (\t -> { row | text = t })


rollText : RowTextComponent -> Generator RowTextComponent
rollText text =
    case text of
        PlainText _ ->
            constant text

        RollableText v ->
            rollValue v
                |> map RollableText


rollValue : { a | var : String, expression : Expr } -> Generator RollableValue
rollValue v =
    rollExpr v.expression
        |> map evaluateExpr
        |> map (\rollTotal -> { var = v.var, expression = v.expression, value = ValueResult rollTotal })


rollOnBundle : Registry -> Context -> Bundle -> Generator Bundle
rollOnBundle registry context bundle =
    List.map (rollOnRef registry context) bundle.tables
        |> Random.Extra.sequence
        |> Random.map (\refs -> { bundle | tables = refs })


otherwiseMaybe : Maybe a -> Maybe a -> Maybe a
otherwiseMaybe value fallback =
    case value of
        Nothing ->
            fallback

        _ ->
            value


rollOnRef : Registry -> Context -> RollableRef -> Generator RollableRef
rollOnRef registry context r =
    let
        newContext =
            addToContextFromRef r context
    in
    case r of
        Ref ref ->
            case findTableSource registry ref.path of
                Just table ->
                    rollOnTable table newContext ref.instructions
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
                            rollOnBundle registry newContext bundle
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
            rollOnBundle registry newContext ref.bundle
                |> Random.map (updateBundle ref)

        RolledTable ref ->
            rollOnRef registry newContext (Ref { path = ref.path, instructions = ref.instructions, title = Just ref.title })


onlyOneRollCount : RollInstructions -> RollInstructions
onlyOneRollCount instructions =
    { instructions | rollCount = Just (ConstValue 1) }


updateRowResult : Int -> TableRollResult -> WithTableResult a -> WithTableResult a
updateRowResult rowIndex newResult rolledTable =
    { rolledTable | result = List.Extra.setAt rowIndex newResult rolledTable.result }


rerollSingleTableRow : Registry -> Context -> RollableRef -> Int -> Generator RollableRef
rerollSingleTableRow registry context r rowIndex =
    case r of
        RolledTable ref ->
            case findTableSource registry ref.path of
                Just table ->
                    let
                        newRowRoll =
                            -- TODO: modify instructions for "ignore" using existing table context
                            rollOnTable table (addToContextFromResults ref.result context) (onlyOneRollCount ref.instructions)
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
