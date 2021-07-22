module RollTablePlayground exposing (main)

import Browser
import Browser.Events exposing (onKeyDown)
import Debounce exposing (Debounce)
import Debug exposing (toString)
import Decode exposing (YamlRow(..))
import Dice exposing (Bundle, DiceError(..), Expr(..), FormulaTerm(..), RegisteredRollable, ResolvedBundle, ResolvedTableRef, Rollable(..), RollableRoller, RolledExpr(..), RolledFormulaTerm(..), RolledRollable(..), RolledRollableResult, RolledTable, TableRef, formulaTermString, rangeString, rollBundle, rollTable)
import Dict
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes exposing (list, placeholder, style)
import Html.Events exposing (onBlur, onClick, onFocus, onInput)
import Json.Decode
import KeyPress exposing (KeyValue, keyDecoder)
import List exposing (indexedMap, length, map)
import List.Extra exposing (getAt, setAt)
import Loader exposing (getDirectory, loadTable)
import Maybe exposing (andThen, withDefault)
import Maybe.Extra
import Msg exposing (Msg(..), RollResultIndex, RollableLoadResult)
import Parse
import Parser
import Random
import Registry exposing (Registry)
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
    | TableLoadingProgress Int Registry
    | TableDirectory Registry


type NestedTableResult
    = InitialRolledTable RolledRollableResult (List NestedTableResult)
    | UnrolledRef TableRef
    | RolledRef TableRef RolledRollableResult (List NestedTableResult)


type alias TableResultList =
    List NestedTableResult


type alias Model =
    { logMessage : List String
    , debounce : Debounce String
    , multiDieCount : Int
    , multiDieSides : Int
    , formula : Result (List Parser.DeadEnd) Expr
    , results : Maybe RolledFormulaTerm
    , tableResults : TableResultList
    , tables : TableDirectoryState
    , tableSearchInput : String
    , tableSearchResults : List String
    , inSearchField : Bool
    , searchResultOffset : Int
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Model [] Debounce.init 3 8 (Result.Err []) Nothing [] TableDirectoryLoading "" [] False 0
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


loadedTable : Model -> RollableLoadResult -> Model
loadedTable model result =
    let
        newDirectoryUpdate =
            case result of
                Ok decodeResult ->
                    case decodeResult of
                        Ok rollable ->
                            Dict.insert rollable.path rollable

                        Err e ->
                            Debug.log ("decodeResult! " ++ Debug.toString e) identity

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


selectedRollable : Model -> Maybe RegisteredRollable
selectedRollable model =
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


resultAtIndex : RollResultIndex -> TableResultList -> Maybe RolledRollableResult
resultAtIndex index list =
    case index of
        [] ->
            Nothing

        [ i ] ->
            getAt i list
                |> andThen
                    (\node ->
                        case node of
                            InitialRolledTable rolledRollable _ ->
                                Just rolledRollable

                            RolledRef _ rolledRollable _ ->
                                Just rolledRollable

                            _ ->
                                Nothing
                    )

        i :: rest ->
            getAt i list
                |> andThen
                    (\node ->
                        case node of
                            InitialRolledTable _ nestedList ->
                                resultAtIndex rest nestedList

                            RolledRef _ _ nestedList ->
                                resultAtIndex rest nestedList

                            _ ->
                                Nothing
                    )


generatorToRerollResult : RolledRollable -> RollableRoller
generatorToRerollResult toReroll =
    case toReroll of
        RolledTable_ tableToReroll ->
            Random.map Ok
                (Random.map RolledTable_ (rollTable tableToReroll.table tableToReroll.table.dice))

        RolledBundle_ bundleToReroll ->
            case rollBundle Dict.empty bundleToReroll.bundle of
                Ok roller ->
                    Random.map Ok (Random.map RolledBundle_ roller)

                Err e ->
                    Random.map Err (Random.constant e)


rerollResultIntoIndex : RollResultIndex -> RolledRollableResult -> Cmd Msg
rerollResultIntoIndex index toReroll =
    case toReroll of
        Err e ->
            Debug.log "cannot reroll invalid result" Cmd.none

        Ok rollable ->
            Random.generate (RerolledTable index) (generatorToRerollResult rollable)


rerollResultAtIndex : RollResultIndex -> Model -> Cmd Msg
rerollResultAtIndex index model =
    Maybe.withDefault Cmd.none
        (resultAtIndex index model.tableResults
            |> andThen
                (rerollResultIntoIndex index >> Just)
        )


tableRefsForRolledTable : RolledRollableResult -> List NestedTableResult
tableRefsForRolledTable result =
    case result of
        Err e ->
            []

        Ok rolledRollable ->
            case rolledRollable of
                RolledTable_ rolledTable ->
                    case rolledTable.row of
                        Ok row ->
                            List.map UnrolledRef row.tableRefs

                        _ ->
                            []

                RolledBundle_ rolledBundle ->
                    []


replaceResult : TableResultList -> RollResultIndex -> RolledRollableResult -> TableResultList
replaceResult list index rolledRollable =
    case index of
        [] ->
            list

        [ i ] ->
            case getAt i list of
                Just (RolledRef ref _ _) ->
                    setAt i (RolledRef ref rolledRollable (tableRefsForRolledTable rolledRollable)) list

                Just (InitialRolledTable _ _) ->
                    setAt i (InitialRolledTable rolledRollable (tableRefsForRolledTable rolledRollable)) list

                Just (UnrolledRef ref) ->
                    setAt i (RolledRef ref rolledRollable (tableRefsForRolledTable rolledRollable)) list

                Nothing ->
                    list

        i :: rest ->
            case getAt i list of
                Just (RolledRef _ _ nested) ->
                    replaceResult nested rest rolledRollable

                Just (InitialRolledTable _ nested) ->
                    replaceResult nested rest rolledRollable

                _ ->
                    list


modelRegistry : Model -> Registry
modelRegistry model =
    case model.tables of
        TableLoadingProgress _ reg ->
            reg

        TableDirectory reg ->
            reg

        _ ->
            Dict.empty


resolveBundleTableRefs : Model -> RegisteredRollable -> Maybe (List ResolvedTableRef)
resolveBundleTableRefs model rollable =
    case rollable.rollable of
        RollableBundle bundle ->
            Maybe.Extra.combine
                (List.map
                    (\ref ->
                        Dict.get ref.path (modelRegistry model)
                            |> Maybe.andThen
                                (\rr ->
                                    case rr.rollable of
                                        RollableTable table ->
                                            Just (ResolvedTableRef table ref)

                                        _ ->
                                            Nothing
                                )
                    )
                    bundle.tables
                )

        _ ->
            Nothing


resolveBundle : Model -> RegisteredRollable -> Maybe ResolvedBundle
resolveBundle model rollable =
    case rollable.rollable of
        RollableBundle bundle ->
            resolveBundleTableRefs model rollable
                |> Maybe.andThen (\trs -> Just (ResolvedBundle trs bundle.title))

        _ ->
            Nothing


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Roll rollRequest ->
            case rollRequest of
                Msg.SelectedTable ->
                    case selectedRollable model of
                        Just rollable ->
                            ( model
                            , case rollable.rollable of
                                RollableTable table ->
                                    Random.generate NewRolledTable
                                        (Random.map Ok
                                            (Random.map
                                                RolledTable_
                                                (rollTable table table.dice)
                                            )
                                        )

                                RollableBundle _ ->
                                    case resolveBundle model rollable of
                                        Nothing ->
                                            Cmd.none

                                        Just bundle ->
                                            (case rollBundle Dict.empty bundle of
                                                Ok roller ->
                                                    Random.map Ok (Random.map RolledBundle_ roller)

                                                Err e ->
                                                    Random.map Err (Random.constant e)
                                            )
                                                |> Random.generate NewRolledTable
                            )

                        _ ->
                            ( model, Cmd.none )

                Msg.Reroll index ->
                    ( model, rerollResultAtIndex index model )

        NewResults newResults ->
            ( { model | results = Just newResults }, Cmd.none )

        RerolledTable index rolledTable ->
            ( { model | tableResults = replaceResult model.tableResults index rolledTable }, Cmd.none )

        NewRolledTable newRolledTable ->
            ( { model | tableResults = model.tableResults ++ [ InitialRolledTable newRolledTable (tableRefsForRolledTable newRolledTable) ] }, Cmd.none )

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
                    Task.perform (\_ -> Roll Msg.SelectedTable) (Task.succeed Nothing)

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
        Err err ->
            case err of
                MissingContextVariable v ->
                    "[Missing context variable " ++ v ++ "]"

                ValueNotMatchingRow v ->
                    "[No row for value=" ++ fromInt v ++ "]"

        Ok row ->
            rangeString row.range ++ ": " ++ row.content


rolledRollableString : RolledRollableResult -> String
rolledRollableString result =
    case result of
        Err e ->
            Debug.toString e

        Ok rollable ->
            case rollable of
                RolledTable_ table ->
                    rolledTableString table

                RolledBundle_ bundle ->
                    String.join " ; "
                        (List.map
                            rolledTableString
                            (List.map .rolled bundle.tables
                                |> List.foldr (++) []
                            )
                        )


rolledTableString : RolledTable -> String
rolledTableString table =
    rolledExprString table.roll
        ++ " = "
        ++ fromInt (Dice.evaluateExpr table.roll)
        ++ " → "
        ++ rowString table.row


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
                                        (if Just path == Maybe.map .path (selectedRollable model) then
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


rollButtonTextForRollable : Rollable -> String
rollButtonTextForRollable rollable =
    case rollable of
        RollableTable table ->
            "Roll " ++ formulaTermString (Ok table.dice)

        RollableBundle _ ->
            "Roll bundle"


rollButtonText : Model -> String
rollButtonText model =
    withDefault "Select a table first"
        (selectedRollable model
            |> Maybe.map (.rollable >> rollButtonTextForRollable)
        )


appendIndex : RollResultIndex -> Int -> RollResultIndex
appendIndex indexPath newIndex =
    indexPath ++ [ newIndex ]


indexPathString : RollResultIndex -> String
indexPathString indexPath =
    "[" ++ String.join "." (List.map fromInt indexPath) ++ "]"


tableRefDisplay : TableRef -> Html Msg
tableRefDisplay tableRef =
    div [] [ text (Debug.toString tableRef) ]


rowTableRefsDisplay : RolledTable -> Html Msg
rowTableRefsDisplay rolledTable =
    case rolledTable.row of
        Ok row ->
            div [] (List.map tableRefDisplay row.tableRefs)

        _ ->
            text ""


tableResultNode : RollResultIndex -> NestedTableResult -> Html Msg
tableResultNode indexPath node =
    div [ style "margin-left" (fromInt (5 * List.length indexPath) ++ "px") ]
        (case node of
            InitialRolledTable rolledRollableResult nested ->
                [ button [ onClick (Roll (Msg.Reroll indexPath)) ] [ text ("↺ " ++ indexPathString indexPath) ]
                , text (rolledRollableString rolledRollableResult)
                , tableResultList indexPath nested
                ]

            RolledRef ref rolledRollableResult nested ->
                [ button [ onClick (Roll (Msg.Reroll indexPath)) ] [ text ("↺ " ++ indexPathString indexPath) ]
                , text (rolledRollableString rolledRollableResult)
                , tableResultList indexPath nested
                ]

            UnrolledRef ref ->
                [ tableRefDisplay ref ]
        )


tableResultList : RollResultIndex -> TableResultList -> Html Msg
tableResultList indexPath list =
    div []
        (indexedMap
            (\i r ->
                let
                    newIndex =
                        appendIndex indexPath i
                in
                tableResultNode newIndex r
            )
            list
        )


view : Model -> Html Msg
view model =
    div []
        [ tableSearch model
        , button [ onClick (Roll Msg.SelectedTable) ] [ text (rollButtonText model) ]
        , tableResultList [] model.tableResults
        ]
