module Icons exposing (..)

-- import FontAwesome.Attributes as Icon
-- import FontAwesome.Brands as Icon
-- import FontAwesome.Layering as Icon
-- import FontAwesome.Svg as SvgIcon
-- import FontAwesome.Transforms as Icon

import Element exposing (Element, html)
import FontAwesome.Icon as Icon
import FontAwesome.Solid as Icon
import FontAwesome.Styles as Icon


css : Element msg
css =
    html Icon.css


roll : Element msg
roll =
    Icon.viewIcon Icon.diceSix |> html


rollMany : Element msg
rollMany =
    Icon.viewIcon Icon.dice |> html
