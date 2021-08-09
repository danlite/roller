module Loader exposing (..)

import Decode exposing (decoder)
import Http
import Json.Decode as J
import Rollable exposing (Rollable)
import String exposing (dropLeft, startsWith)
import Url.Builder exposing (crossOrigin)
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


getDirectory : (Result Http.Error (List String) -> msg) -> Cmd msg
getDirectory message =
    Http.get
        { url = directoryServerUrlRoot
        , expect = Http.expectJson message (J.field "directory" (J.list J.string))
        }


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
                Ok
                    (case
                        Yaml.Decode.fromString
                            (Yaml.Decode.map
                                (Decode.finalize path)
                                decoder
                            )
                            yamlStr
                     of
                        Ok x ->
                            Ok x

                        Err e ->
                            Err (path ++ "\n" ++ Debug.toString e)
                    )
        )


loadTable : (String -> RollableLoadResult -> msg) -> String -> Cmd msg
loadTable message path =
    Http.get
        { url = crossOrigin directoryServerUrlRoot [ withoutLeadingSlash path ] []
        , expect = Http.expectString (decodeTableHttpResult message path)
        }
