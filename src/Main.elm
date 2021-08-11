module Main exposing (..)

import Browser
import Browser.Events exposing (onKeyDown)
import Debounce
import Json.Decode
import KeyPress exposing (keyDecoder)
import Model exposing (Model, Msg(..), TableDirectoryState(..), update)
import UI exposing (ui)


initialModel : Model
initialModel =
    { registry = TableDirectoryLoading
    , results = []
    , tableSearchInput = ""
    , tableSearchFieldText = ""
    , tableSearchResults = []
    , inSearchField = False
    , searchResultOffset = 0
    , debounce = Debounce.init
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( initialModel
    , Cmd.none
      -- , getDirectory GotDirectory
    )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = ui
        , subscriptions = subscriptions
        }


subscriptions : Model -> Sub Msg
subscriptions _ =
    onKeyDown (Json.Decode.map KeyPressTableSearch keyDecoder)
