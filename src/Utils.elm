module Utils exposing (..)


takeAfter : Int -> List a -> List a
takeAfter index list =
    if index < 0 then
        list

    else if index >= List.length list then
        []

    else
        List.reverse list
            |> List.take (List.length list - index - 1)
            |> List.reverse


parentheses : String -> String
parentheses inner =
    "(" ++ inner ++ ")"
