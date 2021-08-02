module V2.Model exposing (..)

import Debounce exposing (Debounce)
import Dict
import Http
import KeyPress exposing (KeyValue)
import List exposing (map)
import List.Extra
import Loader exposing (RollableLoadResult, loadTable)
import Maybe exposing (andThen, withDefault)
import Random
import Search exposing (fuzzySearch)
import Task
import V2.Random exposing (rollOnRef)
import V2.Rollable exposing (IndexPath, Registry, Rollable(..), RollableRef(..), emptyInstructions, refAtIndex, simpleRef)


type alias Model =
    { results : List RollableRef
    , registry : TableDirectoryState
    , tableSearchInput : String
    , tableSearchResults : List String
    , inSearchField : Bool
    , searchResultOffset : Int
    , debounce : Debounce String
    }


type Roll
    = SelectedTable
    | Reroll IndexPath


maxResults : Int
maxResults =
    10



-- Update


rollablePath : Rollable -> String
rollablePath rollable =
    case rollable of
        RollableTable t ->
            t.path

        RollableBundle b ->
            b.path

        MissingRollableError e ->
            e.path


loadedTable : Model -> RollableLoadResult -> Model
loadedTable model result =
    let
        newDirectoryUpdate =
            case result of
                Ok decodeResult ->
                    case decodeResult of
                        Ok rollable ->
                            Dict.insert (rollablePath rollable) rollable

                        Err e ->
                            Debug.log ("decodeResult! " ++ Debug.toString e) identity

                _ ->
                    identity
    in
    case model.registry of
        TableLoadingProgress n dict ->
            case n of
                1 ->
                    { model
                        | registry = TableDirectory (newDirectoryUpdate dict)
                        , tableSearchResults = searchTables "" model
                    }

                _ ->
                    { model | registry = TableLoadingProgress (n - 1) (newDirectoryUpdate dict) }

        _ ->
            model


type TableDirectoryState
    = TableDirectoryLoading
    | TableDirectoryFailed String
    | TableLoadingProgress Int Registry
    | TableDirectory Registry


type Msg
    = Roll Roll
    | DidRoll IndexPath RollableRef
    | RollNew RollableRef
    | GotDirectory (Result Http.Error (List String))
    | LoadTable String
    | LoadedTable String RollableLoadResult
    | InputTableSearch String
    | StartTableSearch String
    | DebounceMsg Debounce.Msg
    | KeyPressTableSearch KeyValue
    | TableSearchFocus Bool


{-| This defines how the debouncer should work.
Choose the strategy for your use case.
-}
debounceConfig : Debounce.Config Msg
debounceConfig =
    { strategy = Debounce.later 200
    , transform = DebounceMsg
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        _ =
            Debug.log "message" msg
    in
    case msg of
        Roll rollWhere ->
            case rollWhere of
                Reroll index ->
                    case ( refAtIndex index model.results, model.registry ) of
                        ( Just ref, TableDirectory registry ) ->
                            ( model, Random.generate (DidRoll index) (rollOnRef registry ref) )

                        _ ->
                            ( model, Cmd.none )

                SelectedTable ->
                    case ( selectedRef model, model.registry ) of
                        ( Just ref, TableDirectory registry ) ->
                            ( model
                            , Random.generate
                                RollNew
                                (rollOnRef registry ref)
                            )

                        _ ->
                            ( model, Cmd.none )

        DidRoll _ _ ->
            -- TODO: replace at index
            ( model, Cmd.none )

        RollNew _ ->
            ( model, Cmd.none )

        GotDirectory result ->
            case result of
                Err e ->
                    ( { model | registry = TableDirectoryFailed (Debug.toString e) }, Cmd.none )

                Ok list ->
                    ( { model | registry = TableLoadingProgress (List.length list) Dict.empty }
                    , Cmd.batch (map (loadTable LoadedTable) list)
                    )

        LoadTable path ->
            ( model, loadTable LoadedTable path )

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
                    Task.perform (\_ -> Roll SelectedTable) (Task.succeed Nothing)

                _ ->
                    Cmd.none

        _ ->
            Cmd.none
    )


selectedRollablePath : Model -> Maybe String
selectedRollablePath model =
    case model.registry of
        TableDirectory _ ->
            List.Extra.getAt model.searchResultOffset model.tableSearchResults

        _ ->
            Nothing


rollableForPath : Model -> String -> Maybe Rollable
rollableForPath model path =
    case model.registry of
        TableDirectory dict ->
            Dict.get path dict

        _ ->
            Nothing


selectedRollable : Model -> Maybe Rollable
selectedRollable model =
    selectedRollablePath model
        |> Maybe.andThen (rollableForPath model)


selectedRef : Model -> Maybe RollableRef
selectedRef model =
    selectedRollablePath model
        |> Maybe.map simpleRef


searchTables : String -> Model -> List String
searchTables tableSearchInput model =
    case model.registry of
        TableDirectory dict ->
            fuzzySearch (Dict.keys dict) tableSearchInput

        _ ->
            []
