module V2.UI exposing (..)

import Element exposing (..)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Html.Attributes
import List.Extra
import String exposing (fromInt)
import V2.Model exposing (Model, Msg(..), Roll(..))
import V2.Rollable
    exposing
        ( IndexPath
        , RollableRef(..)
        , RollableRefData
        , RollableText(..)
        , TableRollResult(..)
        , WithBundle
        , WithTableResult
        , pathString
        )
import V2.UI.Search exposing (search)


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


bundle : IndexPath -> BundleRef -> Element Msg
bundle ip b =
    fullWidthColumn (indexPath ip ++ [ spacing -1 ])
        [ title b.bundle.title (rollButton ip) |> el (width fill :: bordered)
        , children <| mapChildIndexes ip ref b.bundle.tables
        ]


table : IndexPath -> RolledTable -> Element Msg
table ip t =
    fullWidthColumn (indexPath ip ++ [ spacing -1 ]) <|
        tableRollResultsWithTitle
            ip
            (title t.title (rollButton ip))
            t.result


rolledText : List RollableText -> String
rolledText t =
    t
        |> List.map
            (\rt ->
                case rt of
                    PlainText pt ->
                        pt

                    RollableText rv ->
                        Debug.todo "rollablevalue"
            )
        |> String.join
            " "


parentheses : String -> String
parentheses inner =
    "(" ++ inner ++ ")"


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


takeAfter : Int -> List a -> List a
takeAfter index list =
    if index < 0 then
        list

    else if index >= List.length list then
        []

    else
        List.reverse list
            |> List.take (List.length list - index - 1)
            |> List.reverse


tableRollResultsWithTitle : IndexPath -> Element Msg -> List TableRollResult -> List (Element Msg)
tableRollResultsWithTitle ip titleEl res =
    let
        ( firstGroup, firstRefs, secondGroup ) =
            splitTableRollResults res
    in
    (fullWidthColumn bordered <| titleEl :: List.map tableRollResult firstGroup)
        :: (mapChildIndexes ip ref firstRefs |> children)
        :: tableRollResultsWithNoTitle (List.length firstRefs) ip secondGroup


tableRollResultsWithNoTitle : Int -> IndexPath -> List TableRollResult -> List (Element Msg)
tableRollResultsWithNoTitle ipOffset ip res =
    let
        ( firstGroup, firstRefs, secondGroup ) =
            splitTableRollResults res
    in
    case firstGroup of
        [] ->
            []

        _ ->
            (fullWidthColumn bordered <|
                List.map tableRollResult firstGroup
            )
                :: (mapChildIndexesWithOffset ipOffset ip ref firstRefs |> children)
                :: tableRollResultsWithNoTitle (List.length firstRefs) ip secondGroup


tableRollResult : TableRollResult -> Element Msg
tableRollResult res =
    let
        rollRow : Int -> List (Element Msg) -> Element Msg
        rollRow rt els =
            row [ padding 10 ] (rollTotal rt :: els)
    in
    case res of
        RolledRow r ->
            fullWidthColumn []
                [ rollRow
                    r.rollTotal
                    [ rolledText
                        r.result.text
                        |> text
                        |> List.singleton
                        |> paragraph []
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
    column [ height fill, width fill, spacing 10 ]


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
