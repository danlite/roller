module RollTablePlayground exposing (main)

import Browser
import Debug exposing (toString)
import Decode exposing (YamlRow(..))
import Dice exposing (Expr(..), FormulaTerm(..), RolledExpr(..), RolledFormulaTerm(..), RolledTable, formulaTermString, rangeString, rollTable)
import Html exposing (Html, button, div, input, text)
import Html.Attributes exposing (placeholder)
import Html.Events exposing (onClick, onInput)
import List exposing (filterMap, length, map)
import Loader exposing (getDirectory, loadTable)
import Msg exposing (Msg(..))
import Parse
import Parser
import Random
import String exposing (fromInt, toInt)



-- MAIN


main : Program () Model Msg
main =
    Browser.element { init = init, update = update, view = view, subscriptions = subscriptions }



-- MODEL


type alias Model =
    { logMessage : List String
    , multiDieCount : Int
    , multiDieSides : Int
    , formula : Result (List Parser.DeadEnd) Expr
    , results : Maybe RolledFormulaTerm
    , tableResults : Maybe RolledTable
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Model [] 3 8 (Result.Err []) Nothing Nothing
    , getDirectory
    )



-- UPDATE


appendLog : Model -> String -> a -> Model
appendLog m message obj =
    { m | logMessage = m.logMessage ++ [ Debug.toString (Debug.log message obj) ] }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Roll ->
            case model.formula of
                Err _ ->
                    ( model, Cmd.none )

                Ok formula ->
                    case Decode.myTable of
                        Err _ ->
                            ( model, Cmd.none )

                        Ok table ->
                            ( model
                            , Random.generate NewRolledTable
                                (rollTable table formula)
                            )

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
                Err _ ->
                    ( appendLog model "directory result" result, Cmd.none )

                Ok list ->
                    ( model, Cmd.batch (List.map loadTable list) )

        LoadTable path ->
            ( model, loadTable path )

        LoadedTable path result ->
            ( appendLog model ("table result: " ++ path) result, Cmd.none )



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


view : Model -> Html Msg
view model =
    div []
        [ input [ placeholder "dice", onInput (Change Msg.Dice) ] []
        , button [ onClick Roll ] [ text ("ROLL " ++ formulaTermString model.formula) ]
        , div [] [ text (rolledTableString model.tableResults) ]
        ]
