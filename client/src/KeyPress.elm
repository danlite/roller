module KeyPress exposing (KeyValue(..), keyDecoder, toKeyValue)

import Json.Decode as Decode


type KeyValue
    = Character Char
    | Control String


keyDecoder : Decode.Decoder KeyValue
keyDecoder =
    Decode.map toKeyValue (Decode.field "key" Decode.string)


toKeyValue : String -> KeyValue
toKeyValue string =
    case String.uncons string of
        Just ( char, "" ) ->
            Character char

        _ ->
            Control string
