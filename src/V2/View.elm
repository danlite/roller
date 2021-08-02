module V2.View exposing (..)

import Dice exposing (Expr(..))
import Dict
import Html exposing (Attribute, Html, button, div, input, span, text)
import Html.Attributes exposing (attribute, class, placeholder, style)
import Html.Events exposing (onBlur, onClick, onFocus, onInput)
import List.Extra
import Maybe exposing (withDefault)
import Parser
import String exposing (fromInt)
import V2.Model exposing (Model, Msg(..), Roll(..), TableDirectoryState(..), maxResults, rollablePath, selectedRollable)
import V2.Rollable exposing (EvaluatedRow, IndexPath, Rollable(..), RollableRef(..), Row, TableRollResult(..))


refRollableTitle : RollableRef -> String
refRollableTitle ref =
    case ref of
        Ref r ->
            r.path

        RolledTable r ->
            r.title

        BundleRef r ->
            r.bundle.title


rollableRefPath : RollableRef -> String
rollableRefPath r =
    case r of
        Ref ref ->
            ref.path

        RolledTable ref ->
            ref.path

        BundleRef ref ->
            ref.path


rollButton : IndexPath -> String -> Html Msg
rollButton index label =
    button [ onClick (Roll (Reroll index)) ] [ text label ]


rollableRefView : IndexPath -> RollableRef -> Html Msg
rollableRefView index ref =
    case ref of
        Ref info ->
            div
                (class "ref" :: indexClass index)
                [ text info.path, rollButton index ("Roll " ++ info.path) ]

        RolledTable info ->
            div
                (class "rolled-table" :: indexClass index)
                ([ text info.path, rollButton index ("Reroll " ++ info.title) ]
                    ++ List.map (tableRollResultView index) info.result
                )

        BundleRef info ->
            div (class "bundle-ref" :: indexClass index)
                ([ info.bundle.title |> text
                 , rollButton index ("Roll " ++ info.bundle.title)
                 ]
                    ++ bundleTablesView index info.bundle.tables
                )


indexClass : IndexPath -> List (Attribute Msg)
indexClass index =
    let
        margin =
            if List.length index > 1 then
                [ indented ]

            else
                []
    in
    attribute "data-index" (index |> List.map String.fromInt |> String.join ".")
        :: margin


indented : Attribute Msg
indented =
    style "margin-left" "1em"


bundleTablesView : IndexPath -> List RollableRef -> List (Html Msg)
bundleTablesView index tables =
    case tables of
        [] ->
            [ text "" ]

        [ ref ] ->
            [ refResultsSingleView index ref ]

        rollRefs ->
            List.Extra.groupWhile rollablesShouldBeGrouped rollRefs
                |> mapChildIndexes index refResultsGroupView


rollablesShouldBeGrouped : RollableRef -> RollableRef -> Bool
rollablesShouldBeGrouped r1 r2 =
    rollableRefPath r1 == rollableRefPath r2


refResultsSingleView : IndexPath -> RollableRef -> Html Msg
refResultsSingleView index ref =
    div [ class "ref-result-single" ]
        [ rollableRefView index ref ]


refResultsGroupView : IndexPath -> ( RollableRef, List RollableRef ) -> Html Msg
refResultsGroupView index ( firstRef, refs ) =
    case refs of
        [] ->
            refResultsSingleView index firstRef

        _ ->
            div
                [ class "ref-result-multiple" ]
                (mapChildIndexes index rollableRefView (firstRef :: refs))


tableRollResultView : IndexPath -> TableRollResult -> Html Msg
tableRollResultView index result =
    case result of
        MissingRowError err ->
            text ("No row for roll " ++ fromInt err.rollTotal)

        RolledRow info ->
            div [ class "rolled-row", indented ]
                [ rowView index info.rollTotal info.result
                ]


mapChildIndexes : IndexPath -> (IndexPath -> a -> Html Msg) -> List a -> List (Html Msg)
mapChildIndexes index childView children =
    List.indexedMap (\i t -> childView (index ++ [ i ]) t) children


rowView : IndexPath -> Int -> EvaluatedRow -> Html Msg
rowView index rollTotal row =
    -- Row row ->
    --     div [ class "row-raw" ]
    --         ([ text ("(" ++ fromInt rollTotal ++ ") ")
    --          , text row.text
    --          ]
    --             ++ listRefs row.refs
    --         )
    div [ class "row-evaluated" ]
        ([ text ("(" ++ fromInt rollTotal ++ ") "), text (String.join "" (List.map Debug.toString row.text)) ]
            ++ mapChildIndexes index rollableRefView row.refs
        )


resultsView : List RollableRef -> Html Msg
resultsView results =
    div []
        (mapChildIndexes
            []
            rollableRefView
            results
        )


view : Model -> Html Msg
view model =
    div []
        [ tableSearch model
        , button [ onClick (Roll SelectedTable) ] [ text (rollButtonText model) ]
        , resultsView model.results
        ]


tableSearch : Model -> Html Msg
tableSearch model =
    case model.registry of
        TableDirectoryLoading ->
            text "Loading..."

        TableDirectoryFailed e ->
            text ("Error! " ++ e)

        TableLoadingProgress _ dict ->
            text ("Loaded " ++ fromInt (Dict.size dict) ++ " tables...")

        TableDirectory _ ->
            div []
                [ input
                    [ placeholder "Table search"
                    , onInput InputTableSearch
                    , onFocus (TableSearchFocus True)
                    , onBlur (TableSearchFocus False)
                    ]
                    []
                , div []
                    (List.map
                        (\path ->
                            div []
                                [ span
                                    [ style "visibility"
                                        (if Just path == Maybe.map rollablePath (selectedRollable model) then
                                            ""

                                         else
                                            "hidden"
                                        )
                                    ]
                                    [ text "→ " ]
                                , text path
                                ]
                        )
                        (List.take maxResults model.tableSearchResults)
                    )
                ]


formulaTermString : Result (List Parser.DeadEnd) Expr -> String
formulaTermString t =
    case t of
        Err x ->
            Debug.toString x

        Ok expr ->
            case expr of
                Term term ->
                    Dice.formulaTermString term

                Add e1 e2 ->
                    String.join "+" [ formulaTermString (Ok e1), formulaTermString (Ok e2) ]

                Sub e1 e2 ->
                    String.join "-" [ formulaTermString (Ok e1), formulaTermString (Ok e2) ]


rollButtonTextForRollable : Rollable -> String
rollButtonTextForRollable rollable =
    case rollable of
        RollableTable table ->
            "Roll " ++ formulaTermString (Ok table.dice)

        RollableBundle _ ->
            "Roll bundle"

        _ ->
            ""


rollButtonText : Model -> String
rollButtonText model =
    withDefault "Select a table first"
        (selectedRollable model
            |> Maybe.map rollButtonTextForRollable
        )
