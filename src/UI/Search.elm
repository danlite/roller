module UI.Search exposing (expressionString, search)

import Dice exposing (Expr(..))
import Dict
import Element exposing (..)
import Element.Background as Background
import Element.Events exposing (onFocus)
import Element.Input as Input
import Element.Keyed as Keyed
import Html.Attributes
import Html.Events exposing (onBlur)
import Model exposing (Model, Msg(..), Roll(..), TableDirectoryState(..), maxResults, rollablePath, selectedRollable, selectedRollablePath)
import Rollable exposing (Rollable(..))
import String exposing (fromInt)
import UI.Styles exposing (shadow)


loadButton : String -> List String -> Element Msg
loadButton label filters =
    Input.button [] { onPress = Just (RequestDirectory filters), label = text label }


searchField : Model -> Element Msg
searchField model =
    column [ width fill ] <|
        List.singleton <|
            case model.registry of
                TableDirectoryLoading ->
                    row [ width fill, spaceEvenly ]
                        [ loadButton "All" []
                        , loadButton "Lazy DM" [ "/lazy-dm" ]
                        , loadButton "DW PW" [ "/perilous-wilds" ]
                        , loadButton "XGtE" [ "/xgte" ]
                        , loadButton "UNE" [ "/une" ]
                        , loadButton "DMG" [ "/dmg", "/spells" ]

                        -- , loadButton "" ""
                        ]

                TableDirectoryFailed e ->
                    text ("Error! " ++ e)

                TableLoadingProgress _ dict ->
                    text ("Loaded " ++ fromInt (Dict.size dict) ++ " tables...")

                TableDirectory _ ->
                    Input.search
                        [ width fill
                        , onFocus (TableSearchFocus True)
                        , onBlur (TableSearchFocus False) |> htmlAttribute
                        ]
                        { placeholder = Just (Input.placeholder [] (text "Table search"))
                        , onChange = InputTableSearch
                        , text =
                            let
                                selectedPath =
                                    if model.inSearchField then
                                        Nothing

                                    else
                                        selectedRollablePath model
                            in
                            selectedPath |> Maybe.withDefault model.tableSearchFieldText
                        , label = Input.labelHidden "Table search"
                        }


visibleResults : Model -> List String
visibleResults =
    List.take maxResults << .tableSearchResults


searchResults : Model -> Element Msg
searchResults model =
    if model.inSearchField && (List.length (visibleResults model) > 0) then
        searchResultsHelp model

    else
        none


searchResultsHelp : Model -> Element Msg
searchResultsHelp model =
    let
        defaultAttributes =
            [ --  Html.Attributes.style "transition" "flex 0.2s" |> htmlAttribute
              Html.Attributes.style "transition" "max-height 0.2s" |> htmlAttribute
            , Html.Attributes.style "height" "auto" |> htmlAttribute
            ]

        listAttributes =
            defaultAttributes
                ++ (if model.inSearchField then
                        [ Html.Attributes.style "max-height" "200px" |> htmlAttribute
                        ]

                    else
                        [ Html.Attributes.style "max-height" "0" |> htmlAttribute
                        , Html.Attributes.style "opacity" "0" |> htmlAttribute
                        ]
                   )
    in
    column listAttributes <|
        List.map
            (\path ->
                row []
                    [ el
                        [ Html.Attributes.style "visibility"
                            (if Just path == Maybe.map rollablePath (selectedRollable model) then
                                ""

                             else
                                "hidden"
                            )
                            |> htmlAttribute
                        ]
                        (text
                            "→ "
                        )
                    , text path
                    ]
            )
        <|
            visibleResults model


search : Model -> Element Msg
search model =
    Keyed.column
        [ width fill
        , alignBottom
        , padding 10
        , spacing 10
        , Background.color (rgb 0.9 0.9 0.9)
        , shadow -1
        , Html.Attributes.style "z-index" "100" |> htmlAttribute
        ]
        [ ( "results", searchResults model )
        , ( "input"
          , row [ width fill, spacing 10 ]
                [ searchField model
                , rollButton model
                ]
          )
        ]


expressionString : Expr -> String
expressionString expr =
    case expr of
        Term term ->
            Dice.formulaTermString term

        Add e1 e2 ->
            String.join "+" [ expressionString e1, expressionString e2 ]

        Sub e1 e2 ->
            String.join "-" [ expressionString e1, expressionString e2 ]

        Mul e1 e2 ->
            String.join "*" [ expressionString e1, expressionString e2 ]


rollButtonTextForRollable : Rollable -> String
rollButtonTextForRollable rollable =
    case rollable of
        RollableTable table ->
            "Roll " ++ expressionString table.dice

        RollableBundle _ ->
            "Roll bundle"

        _ ->
            ""


rollButton : Model -> Element Msg
rollButton model =
    case model.registry of
        TableDirectory _ ->
            Input.button [] { onPress = Roll SelectedTable |> Just, label = rollButtonText model |> text }

        _ ->
            none


rollButtonText : Model -> String
rollButtonText model =
    Maybe.withDefault "Select a table first"
        (selectedRollable model
            |> Maybe.map rollButtonTextForRollable
        )
