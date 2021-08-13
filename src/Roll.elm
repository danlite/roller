module Roll exposing (..)

import Dice
    exposing
        ( Die
        , Expr(..)
        , FormulaTerm(..)
        , RollableValue
        , RolledPercent(..)
        , RolledValue(..)
        , RowTextComponent(..)
        , rangeMembers
        )
import Dict exposing (Dict)
import List exposing (sum)
import List.Extra
import Maybe exposing (withDefault)
import Parse
import Parser
import Random exposing (..)
import Random.Extra exposing (sequence)
import RollContext exposing (Context, addToContextFromRef, addToContextFromResult, addToContextFromResults, depth, increaseDepth)
import Rollable
    exposing
        ( Bundle
        , EvaluatedRow
        , Registry
        , RollInstructions
        , RollableRef(..)
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


type alias BundleContext =
    Dict String Int


evaluateVariable : Context -> Variable -> Int
evaluateVariable context variable =
    case variable of
        ConstValue v ->
            v

        ContextKey k ->
            case Dict.get k (Tuple.second context) of
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


rollTableExtra : TableSource -> Generator (Maybe (List RowTextComponent))
rollTableExtra table =
    table.extra
        |> Maybe.map
            (\extra ->
                Result.withDefault
                    [ PlainText extra ]
                    (Parser.run Parse.rowText extra)
                    |> rollTextComponents
                    |> map Just
            )
        |> (Maybe.withDefault <| constant <| Nothing)


rollOnTable : Registry -> TableSource -> Context -> RollInstructions -> Generator (List TableRollResult)
rollOnTable registry source context instructions =
    let
        rollCount =
            evaluateVariable context (withDefault (ConstValue 1) instructions.rollCount)
    in
    rollSingleRowOnTable registry context source instructions
        |> andThen
            (\r ->
                if rollCount == 1 then
                    constant r |> map List.singleton

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
                        (constant r)
                        (rollOnTable registry source context modifiedInstructions)
            )


rollRefsIfNotTooDeep : Registry -> Context -> TableRollResult -> Generator TableRollResult
rollRefsIfNotTooDeep registry context res =
    if depth context > 10 then
        constant res

    else
        rollRefsForTableResult
            registry
            (addToContextFromResult res (increaseDepth context))
            res


rollSingleRowOnTable : Registry -> Context -> TableSource -> RollInstructions -> Generator TableRollResult
rollSingleRowOnTable registry context source instructions =
    let
        dice =
            instructions.dice |> withDefault source.dice

        ignore =
            instructions.ignore |> List.map (evaluateVariable context)

        rerolledInputs =
            rollInputs registry context source.inputs
    in
    rollExpr dice
        |> map evaluateExpr
        |> map2 (rollResultForRollOnTable source.rows) rerolledInputs
        |> andThen
            (\r ->
                let
                    rollNumber =
                        rollResultNumber r
                in
                if List.member rollNumber ignore then
                    rollSingleRowOnTable registry context source instructions

                else
                    evaluateRollResult r
                        |> andThen (rollRefsIfNotTooDeep registry context)
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
    rollTextComponents row.text
        |> map (\t -> { row | text = t })


rollTextComponents : List RowTextComponent -> Generator (List RowTextComponent)
rollTextComponents =
    List.map rollText
        >> sequence
        >> andThen rollPercents


rollText : RowTextComponent -> Generator RowTextComponent
rollText text =
    case text of
        RollableText v ->
            rollValue v
                |> map RollableText

        PercentText p ->
            rollTextComponents p.text
                |> map (\t -> PercentText { p | text = t })

        _ ->
            constant text


rollPercents : List RowTextComponent -> Generator (List RowTextComponent)
rollPercents rtcs =
    let
        markSelected : Int -> List RowTextComponent
        markSelected target =
            List.foldl
                (\rtc ( total, newRtcs ) ->
                    case rtc of
                        PercentText p ->
                            if total + p.percent > target then
                                ( -999, PercentText { p | value = PercentResult True } :: newRtcs )

                            else
                                ( total + p.percent, PercentText { p | value = PercentResult False } :: newRtcs )

                        _ ->
                            ( total, rtc :: newRtcs )
                )
                ( 0, [] )
                rtcs
                |> Tuple.mapSecond List.reverse
                |> Tuple.second
    in
    int 1 100
        |> map markSelected


rollValue : { a | var : String, expression : Expr } -> Generator RollableValue
rollValue v =
    rollExpr v.expression
        |> map evaluateExpr
        |> map (\rollTotal -> { var = v.var, expression = v.expression, value = ValueResult rollTotal })


rollOnBundleRefs : Registry -> Context -> List RollableRef -> Generator (List RollableRef)
rollOnBundleRefs registry context refs =
    case List.Extra.uncons refs of
        Nothing ->
            constant []

        Just ( ref, otherRefs ) ->
            rollOnRef registry context ref
                |> andThen
                    (\rolledRef ->
                        map2 (::)
                            (constant rolledRef)
                            (rollOnBundleRefs registry context otherRefs)
                    )


rollOnBundle : Registry -> Context -> Bundle -> Generator Bundle
rollOnBundle registry context bundle =
    rollOnBundleRefs registry context bundle.tables
        |> map (\refs -> { bundle | tables = refs })


otherwiseMaybe : Maybe a -> Maybe a -> Maybe a
otherwiseMaybe value fallback =
    case value of
        Nothing ->
            fallback

        _ ->
            value


rollRefsForTableResult : Registry -> Context -> TableRollResult -> Generator TableRollResult
rollRefsForTableResult registry context res =
    case res of
        RolledRow rr ->
            let
                evalRow =
                    rr.result
            in
            List.map (rollOnRef registry context) evalRow.refs
                |> sequence
                |> map (\refs -> { evalRow | refs = refs })
                |> map (\e -> RolledRow { rr | result = e })

        _ ->
            constant res


rollInputs : Registry -> Context -> Dict comparable RollableRef -> Generator (Dict comparable RollableRef)
rollInputs registry context inputs =
    Dict.map
        (\_ v -> rollOnRef registry context v)
        inputs
        |> mapDict


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
                    map2
                        (\res extra ->
                            RolledTable
                                { path = ref.path
                                , instructions = ref.instructions
                                , result = res
                                , title = ref.instructions.title |> withDefault table.title
                                , extra = extra
                                }
                        )
                        (rollOnTable registry table newContext ref.instructions)
                        (rollTableExtra table)

                _ ->
                    case findBundleSource registry ref.path of
                        Just bundle ->
                            rollOnBundle registry newContext bundle
                                |> map
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
                |> map (updateBundle ref)

        RolledTable ref ->
            rollOnRef registry newContext (Ref { path = ref.path, instructions = ref.instructions, title = Just ref.title })


mapDict : Dict comparable (Generator v) -> Generator (Dict comparable v)
mapDict d =
    Dict.toList d
        |> List.map mapTupleFirst
        |> List.foldl
            (map2
                (\tuple newDict ->
                    Dict.insert (Tuple.first tuple) (Tuple.second tuple) newDict
                )
            )
            (constant Dict.empty)


mapTuple : ( Generator a, Generator b ) -> Generator ( a, b )
mapTuple tuple =
    map2
        Tuple.pair
        (Tuple.first tuple)
        (Tuple.second tuple)


mapTupleFirst : ( a, Generator b ) -> Generator ( a, b )
mapTupleFirst tuple =
    mapTuple <| Tuple.mapFirst constant tuple


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
                            rollOnTable
                                registry
                                table
                                (addToContextFromResults ref.result context)
                                (onlyOneRollCount ref.instructions)
                    in
                    newRowRoll
                        |> map
                            (List.head
                                >> Maybe.map
                                    (\rollResult ->
                                        updateRowResult rowIndex rollResult ref |> RolledTable
                                    )
                                >> Maybe.withDefault r
                            )

                _ ->
                    constant r

        _ ->
            constant r


type alias ExprRoller =
    Generator RolledExpr


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
            map RolledTerm (rollFormulaTerm term)

        Mul e1 e2 ->
            map2 RolledMul (rollExpr e1) (rollExpr e2)

        Add e1 e2 ->
            map2 RolledAdd (rollExpr e1) (rollExpr e2)

        Sub e1 e2 ->
            map2 RolledSub (rollExpr e1) (rollExpr e2)


type alias RolledConstant =
    Int


rollConstant : Int -> FormulaTermRoller
rollConstant c =
    map RolledConstant (constant c)


type RolledFormulaTerm
    = RolledConstant RolledConstant
    | RolledMultiDie RolledMultiDie


type alias FormulaTermRoller =
    Generator RolledFormulaTerm


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
    Generator RolledDie


rollDie : Die -> DieRoller
rollDie die =
    map RolledDie (int 1 die.sides)


type alias RolledMultiDie =
    List RolledDie


type alias MultiDieRoller =
    Generator RolledMultiDie


rollMultiDie :
    { count : Int, sides : Int }
    -> FormulaTermRoller
rollMultiDie multiDie =
    map RolledMultiDie (list multiDie.count (rollDie (Die multiDie.sides)))


type RolledExpr
    = RolledTerm RolledFormulaTerm
    | RolledMul RolledExpr RolledExpr
    | RolledAdd RolledExpr RolledExpr
    | RolledSub RolledExpr RolledExpr


evaluateExpr : RolledExpr -> Int
evaluateExpr expr =
    case expr of
        RolledTerm term ->
            valueOf term

        RolledMul e1 e2 ->
            evaluateExpr e1 * evaluateExpr e2

        RolledAdd e1 e2 ->
            evaluateExpr e1 + evaluateExpr e2

        RolledSub e1 e2 ->
            evaluateExpr e1 - evaluateExpr e2
