module UI.Search exposing (..)

import Dice exposing (Expr(..))
import Dict
import Element exposing (..)
import Element.Background as Background
import Element.Events exposing (onFocus)
import Element.Input as Input
import Html.Attributes
import Html.Events exposing (onBlur)
import Model exposing (Model, Msg(..), Roll(..), TableDirectoryState(..), maxResults, rollablePath, selectedRollable)
import Rollable exposing (Rollable(..))
import String exposing (fromInt)


searchField : Model -> Element Msg
searchField model =
    column [ width fill ] <|
        List.singleton <|
            case model.registry of
                TableDirectoryLoading ->
                    text "Loading..."

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
                        , text = model.tableSearchFieldText
                        , label = Input.labelHidden "Table search"
                        }


searchResults : Model -> Element Msg
searchResults model =
    let
        visibleResults =
            List.take maxResults model.tableSearchResults
    in
    case List.length visibleResults of
        0 ->
            none

        _ ->
            column []
                (List.map
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
                    visibleResults
                )


search : Model -> Element Msg
search model =
    column [ width fill, alignBottom, padding 10, spacing 10, Background.color (rgb 0.9 0.9 0.9) ]
        [ row [ width fill, spacing 10 ]
            [ searchField model
            , Input.button [] { onPress = Roll SelectedTable |> Just, label = rollButtonText model |> text }
            ]
        , searchResults model
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


rollButtonTextForRollable : Rollable -> String
rollButtonTextForRollable rollable =
    case rollable of
        RollableTable table ->
            "Roll " ++ expressionString table.dice

        RollableBundle _ ->
            "Roll bundle"

        _ ->
            ""


rollButtonText : Model -> String
rollButtonText model =
    Maybe.withDefault "Select a table first"
        (selectedRollable model
            |> Maybe.map rollButtonTextForRollable
        )
