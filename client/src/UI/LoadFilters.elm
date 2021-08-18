module UI.LoadFilters exposing (loadFilterButtons)

import Element exposing (Element, text)
import Element.Input as Input
import Model exposing (Msg(..))


loadButton : String -> List String -> Element Msg
loadButton label filters =
    Input.button [] { onPress = Just (RequestDirectoryIndex filters), label = text label }


loadFilterButtons : List (Element Msg)
loadFilterButtons =
    [ loadButton "All" []
    , loadButton "Lazy DM" [ "/lazy-dm" ]
    , loadButton "DW PW" [ "/perilous-wilds" ]
    , loadButton "XGtE" [ "/xgte" ]
    , loadButton "UNE" [ "/une" ]
    , loadButton "DMG" [ "/dmg", "/spells" ]
    , loadButton "Test" [ "/test", "/siblings", "/supplemental/" ]
    ]
