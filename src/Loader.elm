module Loader exposing (..)

import Decode exposing (decoder)
import Http
import Json.Decode as J
import Msg exposing (Msg(..))
import String exposing (dropLeft, startsWith)
import Url.Builder exposing (crossOrigin)
import Yaml.Decode


directoryServerUrlRoot : String
directoryServerUrlRoot =
    "http://localhost:8001"


withoutLeadingSlash : String -> String
withoutLeadingSlash str =
    if startsWith "/" str then
        dropLeft 1 str

    else
        str


getDirectory : Cmd Msg
getDirectory =
    Http.get
        { url = directoryServerUrlRoot
        , expect = Http.expectJson GotDirectory (J.field "directory" (J.list J.string))
        }


decodeTableHttpResult : String -> Result Http.Error String -> Msg
decodeTableHttpResult path result =
    LoadedTable path
        (case result of
            Err err ->
                Err err

            Ok yamlStr ->
                Ok
                    (Yaml.Decode.fromString
                        (Yaml.Decode.map
                            (Decode.finalize (Debug.log "path" path))
                            decoder
                        )
                        (Debug.log "str" yamlStr)
                    )
        )


loadTable : String -> Cmd Msg
loadTable path =
    Http.get
        { url = crossOrigin directoryServerUrlRoot [ withoutLeadingSlash path ] []
        , expect = Http.expectString (decodeTableHttpResult path)
        }
