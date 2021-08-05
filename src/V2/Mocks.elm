module V2.Mocks exposing (..)

import Dice exposing (Range)
import V2.Rollable exposing (Bundle, Path(..), RollInstructions, RollableRef(..), RollableText(..), Row, TableRollResult(..))


mockRow : Row
mockRow =
    { text = "Row", range = Range 1 1, refs = [] }


mockRolledRow : List RollableRef -> TableRollResult
mockRolledRow refs =
    RolledRow
        { result = { refs = refs, text = [ PlainText "PlainText" ] }
        , rollTotal = 3
        }


mockRolledTable : String -> String -> List TableRollResult -> RollableRef
mockRolledTable path title result =
    RolledTable { path = ResolvedPath path, instructions = mockRollInstructions, result = result, title = title }


mockRollInstructions : RollInstructions
mockRollInstructions =
    { title = Nothing
    , rollCount = Nothing
    , total = Nothing
    , dice = Nothing
    , unique = False
    , ignore = []
    , modifier = Nothing
    }


mockTableRef : String -> RollableRef
mockTableRef path =
    Ref
        { path = ResolvedPath path
        , instructions = mockRollInstructions
        , title = Nothing
        }


mockBundleRef : String -> List RollableRef -> RollableRef
mockBundleRef path tables =
    BundleRef { bundle = mockBundle path tables, path = ResolvedPath path, instructions = mockRollInstructions, title = Nothing }


mockBundle : String -> List RollableRef -> Bundle
mockBundle path tables =
    { path = path, title = "MockBundle", tables = tables }



{-
   [0] RollableRef.RolledTable
        - Row
   [1] RollableRef.RolledTable
        - Row
        [1.0] RollableRef.TableRef
        [1.1] RollableRef.Bundle
            [^] Bundle
                [1.1.0] RollableRef.RolledTable
                    - Row
                    - Row
                [1.1.1] RollableRef.RolledTable
                    - Row
                        [1.1.1.0] RollableRef.TableRef
                        [1.1.1.1] RollableRef.TableRef
                    - Row
                        [1.1.1.2] RollableRef.TableRef
   [2] RollableRef.Bundle
       [^] Bundle
           [2.0] RollableRef.TableRef
           [2.1] RollableRef.RolledTable
-}


mockResults : List RollableRef
mockResults =
    [ mockRolledTable "/a/b/c"
        "ABC"
        [ mockRolledRow [] ]
    , mockRolledTable "/d/e/f"
        "DEF"
        [ mockRolledRow
            [ mockTableRef "/g/h/i"
            , mockBundleRef "/j/k/l"
                [ mockRolledTable "/m/n/o"
                    "MNO"
                    [ mockRolledRow []
                    , mockRolledRow []
                    ]
                , mockRolledTable "/p/q/r"
                    "PQR"
                    [ mockRolledRow
                        [ mockTableRef "/s/t/u"
                        , mockTableRef "/y/z/a"
                        ]
                    , mockRolledRow
                        [ mockTableRef "/b/c/d"
                        ]
                    ]
                ]
            ]
        ]
    , mockBundleRef "/v/w/x"
        [ mockTableRef "/1/2/3"
        , mockRolledTable
            "/4/5/6"
            "456"
            [ mockRolledRow [] ]
        ]
    ]
