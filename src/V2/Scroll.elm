module V2.Scroll exposing (..)

import Browser.Dom as Dom
import Task


jumpToBottom : msg -> Cmd msg
jumpToBottom message =
    Dom.getViewportOf "results"
        |> Task.andThen (\info -> Dom.setViewportOf "results" info.viewport.x info.scene.height)
        |> Task.attempt (\_ -> message)
