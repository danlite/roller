module V2.Model exposing (..)

import Dict
import Http
import List exposing (map)
import Loader exposing (RollableLoadResult, loadTable)
import Random
import V2.Random exposing (rollOnRef)
import V2.Rollable exposing (IndexPath, Registry, Rollable(..), RollableRef, refAtIndex)


type alias Model =
    { results : List RollableRef, registry : TableDirectoryState }



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

                        -- , tableSearchResults = searchTables "" model
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
    = Roll IndexPath
    | DidRoll IndexPath RollableRef
    | RollNew RollableRef
    | GotDirectory (Result Http.Error (List String))
    | LoadTable String
    | LoadedTable String RollableLoadResult


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        _ =
            Debug.log "message" msg
    in
    case msg of
        Roll index ->
            case refAtIndex index model.results of
                Just ref ->
                    ( model, Random.generate (DidRoll index) (rollOnRef ref) )

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
