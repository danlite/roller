module UI.Styles exposing (shadow)

import Element exposing (rgba)
import Element.Border as Border


shadow : Float -> Element.Attr decorative msg
shadow yOffset =
    Border.shadow { offset = ( 0, yOffset ), size = 0, blur = 2, color = rgba 0 0 0 0.5 }
