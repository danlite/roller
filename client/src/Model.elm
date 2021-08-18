module Model exposing (..)

import Debounce exposing (Debounce)
import Dict
import Http
import IndexPath exposing (IndexPath)
import KeyPress exposing (KeyValue)
import List exposing (map)
import List.Extra
import Loader exposing (RollableLoadResult, decodeAllDirectoryEntries, decodeNextDirectoryEntry, getDirectoryIndex, loadTable)
import Maybe exposing (withDefault)
import MessageToast exposing (MessageToast)
import Random
import Roll exposing (rerollSingleTableRow, rollOnRef)
import RollContext exposing (Context, refAtIndex)
import Rollable exposing (Registry, Rollable(..), RollableRef(..), replaceAtIndex, simpleRef)
import Scroll exposing (jumpToBottom)
import Search exposing (fuzzySearch)
import String exposing (fromInt)
import Task


type alias Model =
    { results : List RollableRef
    , registry : TableDirectoryState
    , tableSearchFieldText : String
    , tableSearchInput : String
    , tableSearchResults : List String
    , inSearchField : Bool
    , searchResultOffset : Int
    , debounce : Debounce String
    , messageToast : MessageToast Msg
    }


type Roll
    = SelectedTable
    | Reroll IndexPath
    | RerollSingleRow IndexPath Int


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


decodedTable : Result String Rollable -> Model -> Model
decodedTable result model =
    let
        newDirectoryUpdate =
            case result of
                Ok rollable ->
                    Dict.insert (rollablePath rollable) rollable

                Err _ ->
                    identity
    in
    case model.registry of
        TableLoadingProgress n dict ->
            -- case Debug.log "decodedTable" n of
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


loadedTable : Model -> RollableLoadResult -> Model
loadedTable model result =
    case result of
        Ok decodeResult ->
            decodedTable decodeResult model

        _ ->
            model


type TableDirectoryState
    = TableDirectoryLoading
    | TableDirectoryFailed String
    | TableLoadingProgress Int Registry
    | TableDirectory Registry


type Msg
    = NoOp
    | UpdatedSimpleMessageToast (MessageToast Msg)
    | Roll Roll
    | DidRoll IndexPath RollableRef
    | RollNew RollableRef
    | GotDirectory (Result Http.Error (List ( String, String )))
    | DecodedTable (Result String Rollable) (List ( String, String ))
    | RequestDirectoryIndex (List String)
    | GotDirectoryIndex (Result Http.Error (List String))
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


rootContext : Context
rootContext =
    ( 0, Dict.empty )


maybeLog : Bool -> String -> a -> a
maybeLog log _ value =
    if log then
        -- Debug.log message value
        value

    else
        value


showError : String -> Model -> Model
showError message model =
    { model
        | messageToast =
            model.messageToast
                |> MessageToast.danger
                |> MessageToast.withMessage message
    }


showHttpError : Http.Error -> Model -> Model
showHttpError httpError =
    case httpError of
        Http.BadUrl url ->
            showError ("Bad URL: " ++ url)

        Http.Timeout ->
            showError "Request timed out"

        Http.NetworkError ->
            showError "Network error"

        Http.BadStatus status ->
            showError ("Request status " ++ fromInt status)

        Http.BadBody _ ->
            showError "Malformed response body"


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        _ =
            case msg of
                UpdatedSimpleMessageToast _ ->
                    msg

                GotDirectoryIndex _ ->
                    msg

                LoadedTable _ _ ->
                    msg

                LoadTable _ ->
                    msg

                _ ->
                    maybeLog False "message" msg
    in
    case msg of
        NoOp ->
            ( model, Cmd.none )

        UpdatedSimpleMessageToast updatedMessageToast ->
            -- Only needed to re-assign the updated MessageToast to the model.
            ( { model | messageToast = updatedMessageToast }, Cmd.none )

        Roll rollWhere ->
            case rollWhere of
                Reroll index ->
                    case ( refAtIndex index rootContext model.results, model.registry ) of
                        ( Just ( context, ref ), TableDirectory registry ) ->
                            ( model, Random.generate (DidRoll index) (rollOnRef registry context ref) )

                        _ ->
                            ( showError "No rollable found!" model, Cmd.none )

                RerollSingleRow index rowIndex ->
                    case ( refAtIndex index rootContext model.results, model.registry ) of
                        ( Just ( context, ref ), TableDirectory registry ) ->
                            ( model, Random.generate (DidRoll index) (rerollSingleTableRow registry context ref rowIndex) )

                        _ ->
                            ( showError "No row found!" model, Cmd.none )

                SelectedTable ->
                    case ( selectedRef model, model.registry ) of
                        ( Just ref, TableDirectory registry ) ->
                            ( model
                            , Random.generate
                                RollNew
                                (rollOnRef registry rootContext ref)
                            )

                        _ ->
                            ( model, Cmd.none )

        DidRoll index ref ->
            ( { model | results = replaceAtIndex index ref model.results }, Cmd.none )

        RollNew ref ->
            ( { model | results = model.results ++ [ ref ] }, jumpToBottom NoOp )

        GotDirectory res ->
            case res of
                Ok contents ->
                    -- ( { model | registry = TableLoadingProgress (List.length contents) Dict.empty }
                    -- , decodeNextDirectoryEntry DecodedTable contents
                    -- )
                    ( { model | registry = TableDirectory (decodeAllDirectoryEntries contents) }, Cmd.none )

                Err httpError ->
                    ( showHttpError httpError model, Cmd.none )

        DecodedTable res contents ->
            ( decodedTable res model, decodeNextDirectoryEntry DecodedTable contents )

        RequestDirectoryIndex filterString ->
            ( model, getDirectoryIndex filterString GotDirectoryIndex )

        GotDirectoryIndex result ->
            case result of
                Err e ->
                    ( showHttpError e { model | registry = TableDirectoryFailed "" }, Cmd.none )

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
                , tableSearchFieldText = input
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
