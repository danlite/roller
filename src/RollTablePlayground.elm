module RollTablePlayground exposing (main)

import Browser
import Browser.Events exposing (onKeyDown)
import Debounce exposing (Debounce)
import Debug exposing (toString)
import Decode exposing (YamlRow(..))
import Dice exposing (Expr(..), FormulaTerm(..), RolledExpr(..), RolledFormulaTerm(..), RolledTable, Table, formulaTermString, rangeString, rollTable)
import Dict exposing (Dict)
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes exposing (placeholder, style)
import Html.Events exposing (onBlur, onClick, onFocus, onInput)
import Json.Decode
import KeyPress exposing (KeyValue, keyDecoder)
import List exposing (length, map)
import List.Extra
import Loader exposing (getDirectory, loadTable)
import Maybe exposing (andThen, withDefault)
import Msg exposing (Msg(..), TableLoadResult)
import Parse
import Parser
import Random
import Search exposing (fuzzySearch)
import String exposing (fromInt, toInt)
import Task



-- MAIN


main : Program () Model Msg
main =
    Browser.element { init = init, update = update, view = view, subscriptions = subscriptions }



-- MODEL


maxResults : Int
maxResults =
    10


type TableDirectoryState
    = TableDirectoryLoading
    | TableDirectoryFailed String
    | TableLoadingProgress Int (Dict String Table)
    | TableDirectory (Dict String Table)


type alias Model =
    { logMessage : List String
    , debounce : Debounce String
    , multiDieCount : Int
    , multiDieSides : Int
    , formula : Result (List Parser.DeadEnd) Expr
    , results : Maybe RolledFormulaTerm
    , tableResults : Maybe RolledTable
    , tables : TableDirectoryState
    , tableSearchInput : String
    , tableSearchResults : List String
    , inSearchField : Bool
    , searchResultOffset : Int
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Model [] Debounce.init 3 8 (Result.Err []) Nothing Nothing TableDirectoryLoading "" [] False 0
    , getDirectory
    )


{-| This defines how the debouncer should work.
Choose the strategy for your use case.
-}
debounceConfig : Debounce.Config Msg
debounceConfig =
    { strategy = Debounce.later 200
    , transform = DebounceMsg
    }



-- UPDATE


appendLog : Model -> String -> a -> Model
appendLog m message obj =
    { m | logMessage = m.logMessage ++ [ Debug.toString (Debug.log message obj) ] }


loadedTable : Model -> TableLoadResult -> Model
loadedTable model result =
    let
        newDirectoryUpdate =
            case result of
                Ok decodeResult ->
                    case decodeResult of
                        Ok table ->
                            Dict.insert table.path table

                        _ ->
                            identity

                _ ->
                    identity
    in
    case model.tables of
        TableLoadingProgress n dict ->
            case n of
                1 ->
                    { model | tables = TableDirectory (newDirectoryUpdate dict), tableSearchResults = searchTables "" model }

                _ ->
                    { model | tables = TableLoadingProgress (n - 1) (newDirectoryUpdate dict) }

        _ ->
            model


selectedTable : Model -> Maybe Table
selectedTable model =
    case model.tables of
        TableDirectory dict ->
            List.Extra.getAt model.searchResultOffset model.tableSearchResults
                |> andThen (\k -> Dict.get k dict)

        _ ->
            Nothing


searchTables : String -> Model -> List String
searchTables tableSearchInput model =
    case model.tables of
        TableDirectory dict ->
            fuzzySearch (Dict.keys dict) tableSearchInput

        _ ->
            []


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Roll ->
            -- case model.formula of
            --     Err _ ->
            --         ( model, Cmd.none )
            --     Ok formula ->
            --         case Decode.myTable of
            --             Err _ ->
            --                 ( model, Cmd.none )
            --             Ok table ->
            --                 ( model
            --                 , Random.generate NewRolledTable
            --                     (rollTable table formula)
            --                 )
            case selectedTable model of
                Just table ->
                    ( model
                    , Random.generate NewRolledTable
                        (rollTable table table.dice)
                    )

                _ ->
                    ( model, Cmd.none )

        NewResults newResults ->
            ( { model | results = Just newResults }, Cmd.none )

        NewRolledTable newRolledTable ->
            ( { model | tableResults = Just newRolledTable }, Cmd.none )

        Change inputField str ->
            case inputField of
                Msg.Dice ->
                    ( { model | formula = Parser.run Parse.expression str }, Cmd.none )

                _ ->
                    case toInt str of
                        Nothing ->
                            ( model, Cmd.none )

                        Just newVal ->
                            case inputField of
                                Msg.Count ->
                                    ( { model | multiDieCount = newVal }, Cmd.none )

                                Msg.Sides ->
                                    ( { model | multiDieSides = newVal }, Cmd.none )

                                _ ->
                                    ( model, Cmd.none )

        GotDirectory result ->
            case result of
                Err e ->
                    ( { model | tables = TableDirectoryFailed (Debug.toString e) }, Cmd.none )

                Ok list ->
                    ( { model | tables = TableLoadingProgress (List.length list) Dict.empty }, Cmd.batch (map loadTable list) )

        LoadTable path ->
            ( model, loadTable path )

        LoadedTable _ result ->
            ( loadedTable model result, Cmd.none )

        InputTableSearch input ->
            let
                ( debounce, cmd ) =
                    Debounce.push debounceConfig input model.debounce
            in
            ( { model
                | debounce = debounce
              }
            , cmd
            )

        DebounceMsg msg_ ->
            let
                ( debounce, cmd ) =
                    Debounce.update
                        debounceConfig
                        (Debounce.takeLast startTableSearch)
                        msg_
                        model.debounce
            in
            ( { model | debounce = debounce }
            , cmd
            )

        StartTableSearch s ->
            ( { model
                | tableSearchResults = searchTables s model
                , tableSearchInput = s
                , searchResultOffset = 0
              }
            , Cmd.none
            )

        KeyPressTableSearch key ->
            if model.inSearchField then
                handleSearchFieldKey key model

            else
                ( model, Cmd.none )

        TableSearchFocus focus ->
            ( { model | inSearchField = focus }, Cmd.none )


startTableSearch : String -> Cmd Msg
startTableSearch s =
    Task.perform StartTableSearch (Task.succeed s)


offsetForKeyPress : String -> Maybe Int
offsetForKeyPress keyDesc =
    case keyDesc of
        "ArrowDown" ->
            Just 1

        "ArrowUp" ->
            Just -1

        _ ->
            Nothing


handleSearchFieldKey : KeyValue -> Model -> ( Model, Cmd Msg )
handleSearchFieldKey key model =
    ( case key of
        KeyPress.Control keyDesc ->
            withDefault
                model
                (offsetForKeyPress keyDesc
                    |> Maybe.map (\offset -> { model | searchResultOffset = modBy maxResults (model.searchResultOffset + offset) })
                )

        _ ->
            model
    , case key of
        KeyPress.Control keyDesc ->
            case keyDesc of
                "Enter" ->
                    Task.perform (\_ -> Roll) (Task.succeed Nothing)

                _ ->
                    Cmd.none

        _ ->
            Cmd.none
    )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    onKeyDown (Json.Decode.map KeyPressTableSearch keyDecoder)



-- VIEW


rowString : Dice.TableRowRollResult -> String
rowString r =
    case r of
        Err v ->
            "[No row for value=" ++ fromInt v ++ "]"

        Ok row ->
            rangeString row.range ++ ": " ++ row.content


rolledTableString : Maybe RolledTable -> String
rolledTableString table =
    case table of
        Nothing ->
            "[T?]"

        Just table2 ->
            rolledExprString table2.roll
                ++ " = "
                ++ fromInt (Dice.evaluateExpr table2.roll)
                ++ " → "
                ++ rowString table2.row


rolledExprString : RolledExpr -> String
rolledExprString expr =
    case expr of
        RolledAdd e1 e2 ->
            String.join " + " [ rolledExprString e1, rolledExprString e2 ]

        RolledSub e1 e2 ->
            String.join " - " [ rolledExprString e1, rolledExprString e2 ]

        RolledTerm term ->
            rolledFormulaTermString (Just term)


rolledFormulaTermString : Maybe RolledFormulaTerm -> String
rolledFormulaTermString term =
    case term of
        Nothing ->
            ""

        Just term2 ->
            case term2 of
                Dice.RolledConstant c ->
                    toString c

                Dice.RolledMultiDie m ->
                    if length m == 0 then
                        ""

                    else if length m == 1 then
                        String.join "" (map String.fromInt (map .side m))

                    else
                        String.fromInt (List.sum (map .side m))
                            ++ " (= "
                            ++ String.join " + " (map String.fromInt (map .side m))
                            ++ ")"


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


tableSearch : Model -> Html Msg
tableSearch model =
    case model.tables of
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
                                        (if Just path == Maybe.map .path (selectedTable model) then
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


rollButtonText : Model -> String
rollButtonText model =
    withDefault "Select a table first"
        (selectedTable model
            |> Maybe.map .dice
            |> Maybe.map (\expr -> Ok expr)
            |> Maybe.map formulaTermString
            |> Maybe.map (\s -> "Roll " ++ s)
        )


view : Model -> Html Msg
view model =
    div []
        [ tableSearch model
        , button [ onClick Roll ] [ text (rollButtonText model) ]
        , div [] [ text (rolledTableString model.tableResults) ]
        ]
