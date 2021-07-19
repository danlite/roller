module RollTablePlayground exposing (main)

import Browser
import Debug exposing (toString)
import Decode exposing (YamlRow(..))
import Dice exposing (Expr(..), FormulaTerm(..), RolledExpr(..), RolledFormulaTerm(..), RolledTable, Table, formulaTermString, rangeString, rollTable)
import Dict exposing (Dict)
import Html exposing (Html, button, div, input, li, text, ul)
import Html.Attributes exposing (placeholder)
import Html.Events exposing (onClick, onInput)
import List exposing (length, map)
import Loader exposing (getDirectory, loadTable)
import Maybe exposing (andThen)
import Msg exposing (Msg(..), TableLoadResult)
import Parse
import Parser
import Random
import Search exposing (fuzzySearch)
import String exposing (fromInt, toInt)



-- MAIN


main : Program () Model Msg
main =
    Browser.element { init = init, update = update, view = view, subscriptions = subscriptions }



-- MODEL


type TableDirectoryState
    = TableDirectoryLoading
    | TableDirectoryFailed String
    | TableLoadingProgress Int (Dict String Table)
    | TableDirectory (Dict String Table)


type alias Model =
    { logMessage : List String
    , multiDieCount : Int
    , multiDieSides : Int
    , formula : Result (List Parser.DeadEnd) Expr
    , results : Maybe RolledFormulaTerm
    , tableResults : Maybe RolledTable
    , tables : TableDirectoryState
    , tableSearchInput : String
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Model [] 3 8 (Result.Err []) Nothing Nothing TableDirectoryLoading ""
    , getDirectory
    )



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
                    { model | tables = TableDirectory (newDirectoryUpdate dict) }

                _ ->
                    { model | tables = TableLoadingProgress (n - 1) (newDirectoryUpdate dict) }

        _ ->
            model


selectedTable : Model -> Maybe Table
selectedTable model =
    case model.tables of
        TableDirectory dict ->
            List.head (fuzzySearch (Dict.keys dict) model.tableSearchInput)
                |> andThen
                    (\k -> Dict.get k dict)

        _ ->
            Nothing


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
                    ( { model | tables = TableLoadingProgress (List.length list) Dict.empty }, Cmd.batch (List.map loadTable list) )

        LoadTable path ->
            ( model, loadTable path )

        LoadedTable path result ->
            ( loadedTable model result, Cmd.none )

        InputTableSearch input ->
            ( { model | tableSearchInput = input }, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



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

        TableLoadingProgress remaining dict ->
            text ("Loaded " ++ fromInt (Dict.size dict) ++ " tables...")

        TableDirectory dict ->
            div []
                [ input [ placeholder "Table search", onInput InputTableSearch ] []
                , div []
                    (List.indexedMap
                        (\i path ->
                            div []
                                [ text
                                    ((if i == 0 then
                                        "→ "

                                      else
                                        ""
                                     )
                                        ++ path
                                    )
                                ]
                        )
                        (List.take 5 (fuzzySearch (Dict.keys dict) model.tableSearchInput))
                    )
                ]



-- text
--     (String.join "\n" (List.map (\( path, table ) -> path) (Dict.toList dict)))


view : Model -> Html Msg
view model =
    div []
        [ tableSearch model
        , input [ placeholder "dice", onInput (Change Msg.Dice) ] []
        , button [ onClick Roll ] [ text ("ROLL " ++ formulaTermString model.formula) ]
        , div [] [ text (rolledTableString model.tableResults) ]
        ]
