module UI exposing (..)

import Dice exposing (RolledValue(..), RowTextComponent(..))
import Element exposing (..)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Html.Attributes
import List.Extra
import Model exposing (Model, Msg(..), Roll(..))
import Rollable
    exposing
        ( IndexPath
        , RollableRef(..)
        , RollableRefData
        , TableRollResult(..)
        , WithBundle
        , WithTableResult
        , pathString
        )
import String exposing (fromInt)
import UI.Search exposing (expressionString, search)
import Utils exposing (..)


results : List (Element Msg) -> Element Msg
results =
    fullWidthColumn
        [ Html.Attributes.id "results"
            |> htmlAttribute
        , height <|
            minimum 0 fill
        , padding 10
        , spacingXY 0 20
        , scrollbarY
        ]


type alias RolledTable =
    WithTableResult RollableRefData


type alias BundleRef =
    WithBundle RollableRefData


indexPath : IndexPath -> List (Attribute Msg)
indexPath =
    List.map fromInt
        >> String.join "."
        >> Html.Attributes.attribute "data-index-path"
        >> htmlAttribute
        >> List.singleton


bordered =
    [ Border.solid, Border.color (rgb 0 0 0), Border.width 1 ]


fullWidthColumn a =
    column (width fill :: a)


children els =
    case els of
        [] ->
            none

        _ ->
            fullWidthColumn [ paddingEach { top = 0, left = 40, right = 0, bottom = 0 }, spacing -1 ] els


title t btn =
    row [ width fill, padding 10 ] <| [ text t, btn ]


rollButton : IndexPath -> Element Msg
rollButton ip =
    Input.button [ alignRight ] { onPress = Just (Roll (Reroll ip)), label = "roll " ++ (List.map fromInt ip |> String.join ".") |> text }


rollRowButton : IndexPath -> Int -> Element Msg
rollRowButton ip ri =
    Input.button [ alignRight ] { onPress = Just (Roll (RerollSingleRow ip ri)), label = "roll " ++ ((List.map fromInt ip |> String.join ".") ++ ":" ++ fromInt ri) |> text }


bundle : IndexPath -> BundleRef -> Element Msg
bundle ip b =
    fullWidthColumn (indexPath ip ++ [ spacing -1 ])
        [ title b.bundle.title (rollButton ip) |> el (width fill :: bordered)
        , children <| mapChildIndexes ip ref b.bundle.tables
        ]


table : IndexPath -> RolledTable -> Element Msg
table ip t =
    fullWidthColumn (indexPath ip ++ [ spacing -1 ]) <|
        tableRollResults
            ip
            (title t.title (rollButton ip))
            t.result


rolledText : List RowTextComponent -> List (Element Msg)
rolledText =
    List.map
        (\rt ->
            case rt of
                PlainText pt ->
                    text pt

                RollableText rv ->
                    parentheses
                        (case rv.value of
                            ErrorValue ->
                                expressionString rv.expression

                            ValueResult v ->
                                fromInt v

                            UnrolledValue ->
                                expressionString rv.expression
                        )
                        |> (\label -> Input.button [ Html.Attributes.title (expressionString rv.expression) |> htmlAttribute ] { onPress = Nothing, label = text label })
        )


rollTotal : Int -> Element Msg
rollTotal t =
    el [ Font.center, width (px 100), alignTop ] <| text <| parentheses <| fromInt t


hasChildren : TableRollResult -> Bool
hasChildren res =
    case res of
        RolledRow r ->
            List.length r.result.refs > 0

        _ ->
            False


{-| Split a list of TableRollResults to a 3-tuple of:

    (
        results up to and including the first result with any refs;
        the refs of that result, if present;
        the rest of the results
    )

This enables the visual grouping of rows, separated by
any interspersed refs.

-}
splitTableRollResults : List TableRollResult -> ( List TableRollResult, List RollableRef, List TableRollResult )
splitTableRollResults res =
    let
        indexOfFirstResultWithRefs =
            List.Extra.findIndex hasChildren res

        firstResultWithRefs =
            case indexOfFirstResultWithRefs of
                Just i ->
                    List.Extra.getAt i res

                _ ->
                    Nothing
    in
    case ( indexOfFirstResultWithRefs, firstResultWithRefs ) of
        ( Just i, Just (RolledRow rr) ) ->
            ( List.take (i + 1) res, rr.result.refs, takeAfter i res )

        _ ->
            ( res, [], [] )


tableRollResultsHelp : Int -> Int -> IndexPath -> Element Msg -> List TableRollResult -> List (Element Msg)
tableRollResultsHelp riOffset ipOffset ip titleEl res =
    let
        ( firstGroup, firstRefs, secondGroup ) =
            splitTableRollResults res
    in
    case firstGroup of
        [] ->
            []

        _ ->
            (fullWidthColumn bordered <|
                titleEl
                    :: List.indexedMap (\ri r -> tableRollResult ip (ri + riOffset) r) firstGroup
            )
                :: (mapChildIndexesWithOffset ipOffset ip ref firstRefs |> children)
                :: tableRollResultsHelp (riOffset + List.length firstGroup) (List.length firstRefs) ip none secondGroup


tableRollResults : IndexPath -> Element Msg -> List TableRollResult -> List (Element Msg)
tableRollResults =
    tableRollResultsHelp 0 0


tableRollResult : IndexPath -> Int -> TableRollResult -> Element Msg
tableRollResult ip ri res =
    let
        rollRow : Int -> List (Element Msg) -> Element Msg
        rollRow rt els =
            row [ padding 10, width fill ] (rollTotal rt :: els)
    in
    case res of
        RolledRow r ->
            fullWidthColumn []
                [ rollRow
                    r.rollTotal
                    [ rolledText
                        r.result.text
                        |> paragraph []
                    , rollRowButton ip ri
                    ]
                ]

        MissingRowError err ->
            rollRow err.rollTotal
                [ "(X)" |> text ]


ref : IndexPath -> RollableRef -> Element Msg
ref ip rr =
    case rr of
        RolledTable t ->
            table ip t

        BundleRef b ->
            bundle ip b

        Ref r ->
            fullWidthColumn (bordered ++ indexPath ip) [ (pathString r.path |> title) <| rollButton ip ]


app =
    column [ height fill, width fill ]


ui : Model -> Html Msg
ui model =
    app
        [ results <| mapChildIndexes [] ref model.results
        , search model
        ]
        |> layout [ width fill, height (minimum 600 fill) ]


mapChildIndexesWithOffset : Int -> IndexPath -> (IndexPath -> a -> Element Msg) -> List a -> List (Element Msg)
mapChildIndexesWithOffset offset index childView els =
    List.indexedMap (\i t -> childView (index ++ [ i + offset ]) t) els


mapChildIndexes : IndexPath -> (IndexPath -> a -> Element Msg) -> List a -> List (Element Msg)
mapChildIndexes =
    mapChildIndexesWithOffset 0
