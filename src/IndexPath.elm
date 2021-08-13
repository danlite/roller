module IndexPath exposing (IndexPath, toString)

import String exposing (fromInt)


type alias IndexPath =
    List Int


toString : IndexPath -> String
toString ip =
    List.map fromInt ip |> String.join "."
