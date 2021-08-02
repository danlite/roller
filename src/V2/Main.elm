module V2.Main exposing (..)

import Browser
import Loader exposing (getDirectory)
import V2.Mocks exposing (initialModel)
import V2.Model exposing (Model, Msg(..), TableDirectoryState(..), update)
import V2.View exposing (view)


init : () -> ( Model, Cmd Msg )
init _ =
    ( { registry = TableDirectoryLoading, results = initialModel }, getDirectory GotDirectory )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
