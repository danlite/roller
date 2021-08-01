module ModelV2 exposing (..)

import Browser
import Dict exposing (Dict)
import Html exposing (Attribute, Html, button, div, text)
import Html.Attributes exposing (attribute, class, style)
import Html.Events exposing (onClick)
import List.Extra
import Random exposing (Generator)
import Random.Extra
import String exposing (fromInt)


type alias Range =
    Int


type Expr
    = Dice


type RollableValue
    = RollableValue { var : String, expression : Expr }
    | RolledValue { var : String, expression : Expr, value : Int }


type RollableText
    = PlainText String
    | RollableText RollableValue


type Row
    = Row { text : String, range : Range, refs : List RollableRef }
    | EvaluatedRow { text : List RollableText, refs : List RollableRef }


type alias RollInstructions = 
    {}


type alias RollableRefData =
    { path : String, instructions : RollInstructions }


type alias WithRollableSource a =
    { a | rollable : RollableSource }


type alias WithResult a =
    { a | result : List Rollable }


type RollableRef
    = Ref RollableRefData
    | Resolved (WithRollableSource RollableRefData)
    | Rolled (WithResult (WithRollableSource RollableRefData))


type TableRollResult
    = RolledRow { result : Row, rollTotal : Int }
    | MissingRowError { rollTotal : Int }


type alias TableSourceData =
    { path : String, title : String, rows : List Row, inputs : List RollableRef }


type RollableSource
    = TableSource TableSourceData
    | BundleSource Bundle
    | MissingSourceError { path : String }


type Table
    = RegisteredTable TableSourceData
    | RolledTable { path : String, title : String, result : TableRollResult }


type Bundle
    = Bundle { path : String, title : String, tables : List RollableRef }


type Rollable
    = RollableTable Table
    | RollableBundle Bundle
    | MissingRollableError { path : String }


type alias Model =
    List RollableRef



{-
   [0] RollableRef.Rolled
       [^] Table.RolledTable
           - Row
   [1] RollableRef.Rolled
       [^] Table.RolledTable
           - Row
           [1.0] RollableRef.Resolved
               - Table + RollInstructions
           [1.1] RollableRef.Rolled
               [1.1.0] Table.RolledTable
                       - Row
               [1.1.1] Table.RegisteredTable
   [2] RollableRef.Rolled
       [^] Bundle
           [2.0] RollableRef
           [2.1] RollableRef
-}


aRegistry =
    Dict.empty


findTableSource : Dict String RollableSource -> String -> Maybe TableSourceData
findTableSource registry path =
    case Dict.get path registry of
        Just (TableSource data) ->
            Just data

        _ ->
            Nothing


mockRow : Row
mockRow =
    Row { text = "Row", range = 1, refs = [] }


mockRolledRow : List RollableRef -> TableRollResult
mockRolledRow refs =
    RolledRow { result = Row { range = 3, refs = refs, text = "RolledRow" }, rollTotal = 3 }


mockRolledTable : String -> TableRollResult -> Rollable
mockRolledTable path result =
    RollableTable (RolledTable { path = path, title = "RolledTable", result = result })


mockTableSource : String -> RollableSource
mockTableSource path =
    TableSource { path = path, title = "TableSource", rows = [ mockRow, mockRow ], inputs = [] }


mockRegisteredTable : String -> Rollable
mockRegisteredTable path =
    RollableTable (RegisteredTable { path = path, title = "RegisteredTable", rows = [], inputs = [] })


mockRolledRef : String -> List Rollable -> RollableRef
mockRolledRef path rollables =
    Rolled { path = path, instructions = {}, result = rollables, rollable = mockTableSource path }


mockResolvedRef : String -> RollableSource -> RollableRef
mockResolvedRef path rollable =
    Resolved
        { path = path
        , instructions = {}
        , rollable = rollable
        }


mockBundle : String -> List RollableRef -> Rollable
mockBundle path tables =
    RollableBundle
        (Bundle { path = path, title = "MockBundle", tables = tables })


initialModel : Model
initialModel =
    [ mockRolledRef "/a/b/c"
        [ mockRolledTable "/a/b/c"
            (mockRolledRow [])
        ]
    , mockRolledRef "/d/e/f"
        [ mockRolledTable "/d/e/f"
            (mockRolledRow
                [ mockResolvedRef "/g/h/i"
                    (mockTableSource "/g/h/i")
                , mockRolledRef "/j/k/l"
                    [ mockRolledTable "/j/k/l"
                        (mockRolledRow [])
                    , mockRolledTable "/j/k/l"
                        (mockRolledRow [])
                    ]
                , mockRolledRef "/x/y/z"
                    [ mockRolledTable "/x/y/z"
                        (mockRolledRow
                            [ mockResolvedRef "/u/v/w" (mockTableSource "/u/v/w")
                            ]
                        )
                    ]
                ]
            )
        ]
    , mockRolledRef "/m/n/o"
        [ mockBundle "/m/n/o"
            [ Ref { path = "/a/b/c", instructions = {} }
            , mockRolledRef
                "/d/e/f"
                [ mockRolledTable
                    "/d/e/f"
                    (mockRolledRow [])
                ]
            ]
        ]
    ]


tableRollResultRefs : TableRollResult -> List RollableRef
tableRollResultRefs result =
    case result of
        RolledRow r ->
            case r.result of
                Row row ->
                    row.refs

                EvaluatedRow row ->
                    row.refs

        _ ->
            []


rollableRefs : Rollable -> List RollableRef
rollableRefs rollable =
    case rollable of
        RollableBundle (Bundle bundle) ->
            bundle.tables

        RollableTable (RolledTable table) ->
            tableRollResultRefs table.result

        _ ->
            []


refAtIndex : IndexPath -> List RollableRef -> Maybe RollableRef
refAtIndex index model =
    case index of
        [] ->
            Nothing

        [ i ] ->
            List.Extra.getAt i model

        i :: rest ->
            case List.Extra.getAt i model of
                Just (Resolved info) ->
                    case info.rollable of
                        BundleSource (Bundle bundle) ->
                            refAtIndex rest bundle.tables

                        _ ->
                            Nothing

                Just (Rolled info) ->
                    case info.result of
                        [ rollable ] ->
                            refAtIndex rest (rollableRefs rollable)

                        _ ->
                            Nothing

                _ ->
                    Nothing


init : () -> ( Model, Cmd Msg )
init _ =
    ( initialModel, Cmd.none )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }



-- Views


type alias IndexPath =
    List Int


refRollableTitle : RollableRef -> String
refRollableTitle ref =
    case ref of
        Ref r ->
            r.path

        Resolved r ->
            rollableSourceTitle r.rollable

        Rolled r ->
            List.head r.result
                |> Maybe.map rollableTitle
                |> Maybe.withDefault r.path


rollableSourceTitle : RollableSource -> String
rollableSourceTitle rollable =
    case rollable of
        TableSource table ->
            table.title

        BundleSource (Bundle bundle) ->
            bundle.title

        MissingSourceError err ->
            "Could not find " ++ err.path


rollableTitle : Rollable -> String
rollableTitle rollable =
    case rollable of
        RollableTable table ->
            case table of
                RegisteredTable t ->
                    t.title

                RolledTable t ->
                    t.title

        RollableBundle (Bundle bundle) ->
            bundle.title

        MissingRollableError err ->
            "Could not find " ++ err.path


rollablePath : Rollable -> String
rollablePath rollable =
    case rollable of
        RollableTable table ->
            case table of
                RegisteredTable t ->
                    t.path

                RolledTable t ->
                    t.path

        RollableBundle (Bundle bundle) ->
            bundle.path

        MissingRollableError err ->
            err.path


rollButton : IndexPath -> String -> Html Msg
rollButton index label =
    button [ onClick (Roll index) ] [ text label ]


rollableRefView : IndexPath -> RollableRef -> Html Msg
rollableRefView index ref =
    case ref of
        Ref info ->
            div ([ class "ref" ] ++ indexClass index) [ text info.path ]

        Resolved info ->
            div ([ class "ref-resolved" ] ++ indexClass index)
                [ rollableSourceTitle info.rollable |> text
                , rollButton index ("Roll " ++ info.path)
                ]

        Rolled info ->
            div ([ class "ref-rolled" ] ++ indexClass index)
                ([ refRollableTitle ref |> text
                 , rollButton index ("Reroll " ++ info.path)
                 ]
                    ++ refResultsView index info.result
                )


indexClass : IndexPath -> List (Attribute Msg)
indexClass index =
    let
        margin =
            if List.length index > 1 then
                [ indented ]

            else
                []
    in
    attribute "data-index" (index |> List.map String.fromInt |> String.join ".")
        :: margin


indented : Attribute Msg
indented =
    style "margin-left" "1em"


refResultsView : IndexPath -> List Rollable -> List (Html Msg)
refResultsView index results =
    case results of
        [] ->
            [ text "" ]

        [ rollable ] ->
            [ refResultsSingleView index rollable ]

        rollables ->
            List.Extra.groupWhile rollablesShouldBeGrouped rollables
                |> List.map (refResultsGroupView index)


rollablesShouldBeGrouped : Rollable -> Rollable -> Bool
rollablesShouldBeGrouped r1 r2 =
    rollablePath r1 == rollablePath r2


refResultsSingleView : IndexPath -> Rollable -> Html Msg
refResultsSingleView index rollable =
    div [ class "ref-result-single" ]
        [ rollableView index rollable ]


refResultsGroupView : IndexPath -> ( Rollable, List Rollable ) -> Html Msg
refResultsGroupView index ( firstRollable, rollables ) =
    case rollables of
        [] ->
            refResultsSingleView index firstRollable

        _ ->
            div
                [ class "ref-result-multiple" ]
                (mapChildIndexes index rollableView (firstRollable :: rollables))


rollableView : IndexPath -> Rollable -> Html Msg
rollableView index rollable =
    case rollable of
        RollableTable t ->
            tableView index t

        RollableBundle b ->
            case b of
                Bundle bundle ->
                    div [ class "bundle" ]
                        (mapChildIndexes
                            index
                            rollableRefView
                            bundle.tables
                        )

        _ ->
            rollableTitle rollable |> text


tableView : IndexPath -> Table -> Html Msg
tableView index t =
    case t of
        RegisteredTable table ->
            div
                [ class "table-registered" ]
                [ text table.title ]

        RolledTable table ->
            div
                [ class "table-rolled" ]
                [ tableRollResultView index table.result ]


tableRollResultView : IndexPath -> TableRollResult -> Html Msg
tableRollResultView index result =
    case result of
        MissingRowError err ->
            text ("No row for roll " ++ fromInt err.rollTotal)

        RolledRow info ->
            div [ class "rolled-row", indented ]
                [ rowView index info.rollTotal info.result
                ]


mapChildIndexes : IndexPath -> (IndexPath -> a -> Html Msg) -> List a -> List (Html Msg)
mapChildIndexes index childView children =
    List.indexedMap (\i t -> childView (index ++ [ i ]) t) children


rowView : IndexPath -> Int -> Row -> Html Msg
rowView index rollTotal r =
    let
        listRefs =
            mapChildIndexes index rollableRefView
    in
    case r of
        Row row ->
            div [ class "row-raw" ]
                ([ text ("(" ++ fromInt rollTotal ++ ") ")
                 , text row.text
                 ]
                    ++ listRefs row.refs
                )

        EvaluatedRow row ->
            div [ class "row-evaluated" ]
                ([ text ("(" ++ fromInt rollTotal ++ ") "), text (String.join "" (List.map Debug.toString row.text)) ]
                    ++ listRefs row.refs
                )


view : Model -> Html Msg
view model =
    div [] (mapChildIndexes [] rollableRefView model)



-- Update


type Msg
    = Roll IndexPath
    | DidRoll IndexPath RollableRef
    | RollNew RollableRef


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        _ =
            Debug.log "message" msg
    in
    case msg of
        Roll index ->
            case refAtIndex index model of
                Just ref ->
                    ( model, Random.generate (DidRoll index) (rollOnRef ref) )

                _ ->
                    ( model, Cmd.none )

        DidRoll index ref ->
            -- TODO: replace at index
            ( model, Cmd.none )

        RollNew ref ->
            ( model, Cmd.none )



-- Random generation


rollResultForRollOnTable : List Row -> Int -> TableRollResult
rollResultForRollOnTable rows rollTotal =
    case List.Extra.getAt (rollTotal - 1) rows of
        Just row ->
            RolledRow { result = row, rollTotal = rollTotal }

        _ ->
            MissingRowError { rollTotal = rollTotal }


pickRowFromTable : List Row -> Generator TableRollResult
pickRowFromTable rows =
    Random.map (rollResultForRollOnTable rows) (Random.int 1 (List.length rows))


rollOnTable : RollInstructions -> TableSourceData -> Generator Table
rollOnTable instructions source =
    -- TODO: obey instructions for rollCount > 1 (TBD: row ranges, reroll, unique)
    pickRowFromTable source.rows
        |> Random.map (\r -> RolledTable { path = source.path, title = source.title, result = r })


rollOnBundle : Bundle -> Generator Bundle
rollOnBundle b =
    case b of
        Bundle bundle ->
            List.map rollOnRef bundle.tables
                |> Random.Extra.sequence
                |> Random.map (\refs -> Bundle { bundle | tables = refs })


rollOnRollable : RollInstructions -> RollableSource -> Generator (List Rollable)
rollOnRollable instructions rollable =
    case rollable of
        TableSource tableSource ->
            rollOnTable instructions tableSource
                |> Random.map RollableTable
                |> Random.map List.singleton

        BundleSource bundle ->
            rollOnBundle bundle
                |> Random.map RollableBundle
                |> Random.map List.singleton

        _ ->
            Random.constant []


rollOnRef : RollableRef -> Generator RollableRef
rollOnRef r =
    case r of
        Resolved ref ->
            rollOnRefHelp ref

        Rolled ref ->
            rollOnRefHelp ref

        _ ->
            Random.constant r


rollOnRefHelp : { a | path : String, instructions : RollInstructions, rollable : RollableSource } -> Generator RollableRef
rollOnRefHelp ref =
    rollOnRollable ref.instructions ref.rollable
        |> Random.map
            (\result ->
                Rolled
                    { path = ref.path
                    , instructions = ref.instructions
                    , result = result
                    , rollable = ref.rollable
                    }
            )
