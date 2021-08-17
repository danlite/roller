module Search exposing (..)

import Fuzzy exposing (..)


{-| UNUSED
-}
splitInputWithSlashes : String -> String
splitInputWithSlashes input =
    String.join "/" (String.split "" input)


fuzzySearch : List String -> String -> List String
fuzzySearch terms input =
    let
        simpleMatch config separators needle hay =
            match config separators needle hay |> .score
    in
    List.sortBy (simpleMatch [] [ "/" ] input) terms
