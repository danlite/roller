module Loader exposing (..)

import Decode exposing (decoder)
import Dict exposing (Dict)
import Http
import Json.Decode as J
import List.Extra
import Rollable exposing (Rollable)
import String exposing (dropLeft, startsWith)
import Task
import Url.Builder exposing (relative)
import Yaml.Decode


type alias RollableLoadResult =
    Result Http.Error (Result String Rollable)


directoryServerUrlRoot : String
directoryServerUrlRoot =
    "http://localhost:8001"


withoutLeadingSlash : String -> String
withoutLeadingSlash str =
    if startsWith "/" str then
        dropLeft 1 str

    else
        str


withYmlExtension : String -> String
withYmlExtension str =
    str ++ ".yml"


decodeNextDirectoryEntry : (Result String Rollable -> List ( String, String ) -> msg) -> List ( String, String ) -> Cmd msg
decodeNextDirectoryEntry rollableLoadedMsg contents =
    List.Extra.uncons contents
        |> Maybe.map
            (\( ( path, yamlStr ), rest ) ->
                Task.succeed ()
                    |> Task.perform
                        (\_ ->
                            (rollableLoadedMsg <| decodeRollableYaml path yamlStr) <| rest
                        )
            )
        |> Maybe.withDefault Cmd.none


decodeAllDirectoryEntries : List ( String, String ) -> Dict String Rollable
decodeAllDirectoryEntries =
    Dict.fromList
        << List.filterMap
            (\( path, yamlStr ) ->
                case decodeRollableYaml path yamlStr of
                    Ok rollable ->
                        Just ( path, rollable )

                    _ ->
                        Nothing
            )



-- List.Extra.uncons contents
--     |> Maybe.map
--         (\( ( path, yamlStr ), rest ) ->
--             Task.succeed ()
--                 |> Task.perform
--                     (\_ ->
--                         (rollablesLoadedMsg <| decodeRollableYaml path yamlStr) <| rest
--                     )
--         )
--     |> Maybe.withDefault Cmd.none


decodeDirectoryContents : (Result String Rollable -> msg) -> Dict String String -> Cmd msg
decodeDirectoryContents rollableLoadedMsg =
    Cmd.batch
        << (Dict.toList
                >> List.map
                    (\( path, contents ) ->
                        Task.succeed ()
                            |> Task.perform
                                (\_ ->
                                    rollableLoadedMsg <| decodeRollableYaml path contents
                                )
                    )
           )


getDirectory : (Result Http.Error (List ( String, String )) -> msg) -> Cmd msg
getDirectory directoryLoadedMsg =
    Http.get
        { url = "/assets/rollables/rollables.json"
        , expect =
            Http.expectJson
                directoryLoadedMsg
                (J.map Dict.toList (J.dict J.string))
        }


getDirectoryIndex : List String -> (Result Http.Error (List String) -> msg) -> Cmd msg
getDirectoryIndex filterStrings message =
    Http.get
        { url = relative [ "/assets/rollables/index.json" ] ((List.map <| Url.Builder.string "filter") <| filterStrings)
        , expect = Http.expectJson message (J.list J.string)
        }


decodeRollableYaml : String -> String -> Result String Rollable
decodeRollableYaml path yamlStr =
    case
        Yaml.Decode.fromString
            (Yaml.Decode.map
                (Decode.finalize path)
                decoder
            )
            yamlStr
    of
        Ok decoded ->
            Ok decoded

        Err e ->
            Err (path ++ "\n" ++ Yaml.Decode.errorToString e)


decodeTableHttpResult :
    (String -> RollableLoadResult -> msg)
    -> String
    -> Result Http.Error String
    -> msg
decodeTableHttpResult message path result =
    message path
        (case result of
            Err err ->
                Err err

            Ok yamlStr ->
                Ok <| decodeRollableYaml path yamlStr
        )


loadTable : (String -> RollableLoadResult -> msg) -> String -> Cmd msg
loadTable message path =
    Http.get
        { url = relative [ "/assets/rollables/source", withYmlExtension <| withoutLeadingSlash path ] []
        , expect = Http.expectString (decodeTableHttpResult message path)
        }
