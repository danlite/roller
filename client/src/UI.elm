module UI exposing (..)

import Dice exposing (InputPlaceholderModifier(..), RolledPercent(..), RolledValue(..), RowTextComponent(..))
import Dict
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Html.Attributes
import Icons
import IndexPath exposing (IndexPath)
import List.Extra
import Model exposing (Model, Msg(..), Roll(..))
import Rollable
    exposing
        ( Bundle
        , BundleRollResults(..)
        , Inputs
        , RollableRef(..)
        , RollableRefData
        , TableRollResult(..)
        , WithBundle
        , WithTableResult
        , indexForInputPlaceholder
        , pathString
        , rolledInputTextForKeyAtIndex
        )
import String exposing (fromInt)
import UI.Search exposing (expressionString, search)
import UI.Styles exposing (shadow)
import Utils exposing (..)


scaled : Int -> Int
scaled =
    modular 16 1.25 >> round


unit : Int
unit =
    8


halfUnit : Int
halfUnit =
    4


results : List (Element Msg) -> Element Msg
results =
    fullWidthColumn
        [ Html.Attributes.id "results"
            |> htmlAttribute
        , height <|
            minimum 0 fill
        , padding unit
        , spacingXY 0 (unit * 2)
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


above : IndexPath -> Attribute msg
above ip =
    htmlAttribute <| Html.Attributes.style "z-index" <| fromInt (100 - List.length ip)


bordered : List (Attribute msg)
bordered =
    [ Border.solid
    , Border.color (rgb 0 0 0)
    , Border.width 1
    , shadow 1
    ]


depthColorPalette : List Color
depthColorPalette =
    [ ( 250, 233, 220 )
    , ( 252, 244, 224 )
    , ( 222, 239, 235 )
    , ( 221, 235, 247 )
    , ( 233, 224, 246 )
    , ( 247, 220, 235 )
    , ( 252, 222, 224 )
    ]
        |> List.map (\( r, g, b ) -> rgb255 r g b)


depthColor : IndexPath -> Attribute msg
depthColor ip =
    List.Extra.getAt ((modBy <| List.length depthColorPalette) <| List.length ip) depthColorPalette
        |> Maybe.withDefault (rgb 1 1 1)
        |> Background.color


depthColorMonochrome : IndexPath -> Attribute msg
depthColorMonochrome ip =
    let
        value =
            1.0 - (0.04 * toFloat (List.length ip - 1))
    in
    Background.color <|
        rgb value value value


fullWidthColumn : List (Attribute msg) -> List (Element msg) -> Element msg
fullWidthColumn a =
    column (width fill :: a)


children : List (Element msg) -> Element msg
children els =
    case els of
        [] ->
            none

        _ ->
            fullWidthColumn
                [ paddingEach { top = 0, left = unit * 4, right = 0, bottom = 0 }
                , spacing -1
                ]
                els


title : String -> Element msg -> Element msg
title t btn =
    row [ width fill, padding unit ] <| [ text t, btn ]


rollButton : IndexPath -> Element Msg
rollButton ip =
    Input.button [ alignRight, padding halfUnit ]
        { onPress = Just (Roll (Reroll ip))
        , label =
            paragraph []
                [ Icons.rollMany

                -- , IndexPath.toString ip |> text
                ]
        }


rollRowButton : IndexPath -> Int -> Element Msg
rollRowButton ip ri =
    Input.button [ alignRight, padding halfUnit ]
        { onPress = Just (Roll (RerollSingleRow ip ri))
        , label =
            paragraph []
                [ Icons.roll

                -- , IndexPath.toString ip |> text
                ]
        }


bundleRef : IndexPath -> BundleRef -> Element Msg
bundleRef ip b =
    case b.result of
        UnrolledBundleRef ->
            fullWidthColumn (indexPath ip ++ [ spacing -1 ])
                [ title b.bundle.title (rollButton ip)
                    |> el ([ width fill, above ip, depthColor ip ] ++ bordered)
                ]

        RolledBundles res ->
            fullWidthColumn (indexPath ip ++ [ spacing -1 ]) <|
                mapChildIndexes ip bundle res


bundle : IndexPath -> Bundle -> Element Msg
bundle ip b =
    fullWidthColumn (indexPath ip ++ [ spacing -1 ])
        [ title b.title (rollButton ip)
            |> el ([ width fill, above ip, depthColor ip ] ++ bordered)
        , children <| mapChildIndexes ip ref b.tables
        ]


tableExtraText : RolledTable -> Element Msg
tableExtraText t =
    t.extra
        |> Maybe.map (row [ width fill, padding unit ] << rolledText Dict.empty)
        |> Maybe.withDefault none


table : IndexPath -> RolledTable -> Element Msg
table ip t =
    fullWidthColumn (indexPath ip ++ [ spacing -1 ]) <|
        tableRollResults
            ip
            [ title t.title
                (if List.length t.result > 1 then
                    rollButton ip

                 else
                    none
                )
            , tableExtraText t
            ]
            t.result


colorFromString : String -> Maybe Color
colorFromString =
    colorFromStringWithIntensity 150


brightColorFromString : String -> Maybe Color
brightColorFromString =
    colorFromStringWithIntensity 255


colorFromStringWithIntensity : Int -> String -> Maybe Color
colorFromStringWithIntensity v s =
    case s of
        "green" ->
            Just <| rgb255 0 v 0

        "yellow" ->
            Just <| rgb255 v v 0

        "cyan" ->
            Just <| rgb255 0 v v

        "magenta" ->
            Just <| rgb255 v 0 v

        _ ->
            Nothing


attributesForInputPlaceholder : List InputPlaceholderModifier -> List (Attribute Msg)
attributesForInputPlaceholder mods =
    let
        color : List (Attribute Msg)
        color =
            List.Extra.findMap
                (\m ->
                    case m of
                        InputPlaceholderColor c ->
                            Just c

                        _ ->
                            Nothing
                )
                mods
                |> Maybe.andThen colorFromString
                |> Maybe.map Font.color
                |> Maybe.map List.singleton
                |> Maybe.withDefault []

        bgColor : List (Attribute Msg)
        bgColor =
            List.Extra.findMap
                (\m ->
                    case m of
                        InputPlaceholderBackgroundColor c ->
                            Just c

                        _ ->
                            Nothing
                )
                mods
                |> Maybe.andThen brightColorFromString
                |> Maybe.map
                    (\c ->
                        [ Border.shadow
                            { offset = ( 0, 0 )
                            , blur = 0
                            , size = 1
                            , color = c
                            }
                        , Background.color c
                        ]
                    )
                |> Maybe.withDefault []
    in
    color ++ bgColor


textForInputPlaceholder : List InputPlaceholderModifier -> String -> Element Msg
textForInputPlaceholder mods initialText =
    let
        lowercase =
            List.Extra.findMap
                (\m ->
                    case m of
                        InputPlaceholderTextTransform _ ->
                            Just String.toLower

                        _ ->
                            Nothing
                )
                mods
                |> Maybe.withDefault identity

        transforms =
            [ lowercase ]
    in
    List.foldl (<|) initialText transforms |> text


rolledText : Inputs -> List RowTextComponent -> List (Element Msg)
rolledText inputs =
    List.map
        (\rt ->
            case rt of
                PlainText pt ->
                    text pt

                InputPlaceholder key mods ->
                    Maybe.withDefault
                        ("?" ++ key ++ "?")
                        (rolledInputTextForKeyAtIndex key (indexForInputPlaceholder mods) inputs)
                        |> textForInputPlaceholder mods
                        |> el (attributesForInputPlaceholder mods)

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
                        |> (\label ->
                                Input.button
                                    [ Html.Attributes.title
                                        (expressionString rv.expression)
                                        |> htmlAttribute
                                    ]
                                    { onPress = Nothing, label = text label }
                           )

                PercentText pt ->
                    pt.text
                        |> rolledText inputs
                        |> paragraph
                            (case pt.value of
                                PercentResult True ->
                                    [ Font.bold ]

                                _ ->
                                    [ Font.color <| rgba 0 0 0 0.5 ]
                            )
        )


rollTotal : Int -> Element Msg
rollTotal t =
    el
        [ alignTop
        , width (px 80)
        ]
    <|
        el
            [ Font.center
            , Font.size <| scaled -1
            , width (px 30)
            , height (px 30)
            , centerX
            , Background.color <| rgba 0 0 0 0.2
            , Font.color <| rgb 1 1 1
            , Border.rounded 4
            ]
        <|
            el
                [ centerX
                , centerY
                ]
            <|
                text <|
                    fromInt t


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


tableRollResultsHelp :
    Int
    -> Int
    -> IndexPath
    -> List (Element Msg)
    -> List TableRollResult
    -> List (Element Msg)
tableRollResultsHelp riOffset ipOffset ip headerEls res =
    let
        ( firstGroup, firstRefs, secondGroup ) =
            splitTableRollResults res

        firstGroupStyle =
            (++) (depthColor ip :: bordered) <|
                if List.length firstRefs > 0 then
                    [ above ip ]

                else
                    []
    in
    case firstGroup of
        [] ->
            []

        _ ->
            (fullWidthColumn firstGroupStyle <|
                headerEls
                    ++ List.indexedMap
                        (\ri r -> tableRollResult ip (ri + riOffset) r)
                        firstGroup
            )
                :: (mapChildIndexesWithOffset
                        ipOffset
                        ip
                        ref
                        firstRefs
                        |> children
                   )
                :: tableRollResultsHelp
                    (riOffset + List.length firstGroup)
                    (ipOffset + List.length firstRefs)
                    ip
                    []
                    secondGroup


tableRollResults : IndexPath -> List (Element Msg) -> List TableRollResult -> List (Element Msg)
tableRollResults =
    tableRollResultsHelp 0 0


tableRollResult : IndexPath -> Int -> TableRollResult -> Element Msg
tableRollResult ip ri res =
    let
        rollRow : Int -> List (Element Msg) -> Element Msg
        rollRow rt els =
            row [ padding unit, width fill ] (rollTotal rt :: els)
    in
    case res of
        RolledRow r ->
            fullWidthColumn []
                [ rollRow
                    r.rollTotal
                    [ rolledText
                        r.inputs
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
            bundleRef ip b

        Ref r ->
            fullWidthColumn
                (bordered ++ indexPath ip)
                [ (pathString r.path |> title) <| rollButton ip ]


app : List (Element msg) -> Element msg
app =
    column [ height fill, width fill ]


ui : Model -> Html Msg
ui model =
    app
        [ Icons.css
        , results <| mapChildIndexes [] ref model.results
        , search model
        ]
        |> layout [ width fill, height (minimum 600 fill), Font.size <| scaled 1 ]


mapChildIndexesWithOffset : Int -> IndexPath -> (IndexPath -> a -> Element Msg) -> List a -> List (Element Msg)
mapChildIndexesWithOffset offset index childView els =
    List.indexedMap (\i t -> childView (index ++ [ i + offset ]) t) els


mapChildIndexes : IndexPath -> (IndexPath -> a -> Element Msg) -> List a -> List (Element Msg)
mapChildIndexes =
    mapChildIndexesWithOffset 0


childIndex : IndexPath -> IndexPath
childIndex =
    (++) [ 0 ]
