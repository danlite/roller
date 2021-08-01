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


type alias WithBundle a =
    { a | bundle : Bundle }


type alias WithTableResult a =
    { a | result : List TableRollResult, title : String }


type RollableRef
    = Ref RollableRefData
    | BundleRef (WithBundle RollableRefData)
    | RolledTable (WithTableResult RollableRefData)


type TableRollResult
    = RolledRow { result : Row, rollTotal : Int }
    | MissingRowError { rollTotal : Int }


type alias TableSource =
    { rows : List Row
    , inputs : List RollableRef
    , path : String
    , title : String
    }


type alias Bundle =
    { path : String, title : String, tables : List RollableRef }


type Rollable
    = RollableTable TableSource
    | RollableBundle Bundle
    | MissingRollableError { path : String }


type alias Model =
    List RollableRef


type alias Registry =
    Dict String Rollable


aRegistry : Registry
aRegistry =
    Dict.empty


findTableSource : Registry -> String -> Maybe TableSource
findTableSource registry path =
    case Dict.get path registry of
        Just (RollableTable data) ->
            Just data

        _ ->
            Nothing


findBundleSource : Registry -> String -> Maybe Bundle
findBundleSource registry path =
    case Dict.get path registry of
        Just (RollableBundle data) ->
            Just data

        _ ->
            Nothing


mockRow : Row
mockRow =
    Row { text = "Row", range = 1, refs = [] }


mockRolledRow : List RollableRef -> TableRollResult
mockRolledRow refs =
    RolledRow { result = Row { range = 3, refs = refs, text = "RolledRow" }, rollTotal = 3 }


mockRolledTable : String -> String -> List TableRollResult -> RollableRef
mockRolledTable path title result =
    RolledTable { path = path, instructions = {}, result = result, title = title }


mockTableRef : String -> RollableRef
mockTableRef path =
    Ref
        { path = path
        , instructions = {}
        }


mockBundleRef : String -> List RollableRef -> RollableRef
mockBundleRef path tables =
    BundleRef { bundle = mockBundle path tables, path = path, instructions = {} }


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
   [2] RollableRef.Bundle
       [^] Bundle
           [2.0] RollableRef.TableRef
           [2.1] RollableRef.RolledTable
-}


initialModel : Model
initialModel =
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


refsForRow : Row -> List RollableRef
refsForRow row =
    case row of
        Row r ->
            r.refs

        EvaluatedRow r ->
            r.refs


refAtIndex : IndexPath -> List RollableRef -> Maybe RollableRef
refAtIndex index model =
    case index of
        [] ->
            Nothing

        [ i ] ->
            List.Extra.getAt i model

        i :: rest ->
            case List.Extra.getAt i model of
                Just (BundleRef bundleRef) ->
                    refAtIndex rest bundleRef.bundle.tables

                Just (RolledTable info) ->
                    case info.result of
                        [ rollResult ] ->
                            case rollResult of
                                RolledRow rolledRow ->
                                    refAtIndex rest (refsForRow rolledRow.result)

                                _ ->
                                    Nothing

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

        RolledTable r ->
            r.title

        BundleRef r ->
            r.bundle.title


rollableRefPath : RollableRef -> String
rollableRefPath r =
    case r of
        Ref ref ->
            ref.path

        RolledTable ref ->
            ref.path

        BundleRef ref ->
            ref.path


rollButton : IndexPath -> String -> Html Msg
rollButton index label =
    button [ onClick (Roll index) ] [ text label ]


rollableRefView : IndexPath -> RollableRef -> Html Msg
rollableRefView index ref =
    case ref of
        Ref info ->
            div
                (class "ref" :: indexClass index)
                [ text info.path, rollButton index ("Roll " ++ info.path) ]

        RolledTable info ->
            div
                (class "rolled-table" :: indexClass index)
                ([ text info.path, rollButton index ("Reroll " ++ info.title) ]
                    ++ List.map (tableRollResultView index) info.result
                )

        BundleRef info ->
            div (class "bundle-ref" :: indexClass index)
                ([ info.bundle.title |> text
                 , rollButton index ("Roll " ++ info.bundle.title)
                 ]
                    ++ bundleTablesView index info.bundle.tables
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


bundleTablesView : IndexPath -> List RollableRef -> List (Html Msg)
bundleTablesView index tables =
    case tables of
        [] ->
            [ text "" ]

        [ ref ] ->
            [ refResultsSingleView index ref ]

        rollRefs ->
            List.Extra.groupWhile rollablesShouldBeGrouped rollRefs
                |> mapChildIndexes index refResultsGroupView


rollablesShouldBeGrouped : RollableRef -> RollableRef -> Bool
rollablesShouldBeGrouped r1 r2 =
    rollableRefPath r1 == rollableRefPath r2


refResultsSingleView : IndexPath -> RollableRef -> Html Msg
refResultsSingleView index ref =
    div [ class "ref-result-single" ]
        [ rollableRefView index ref ]


refResultsGroupView : IndexPath -> ( RollableRef, List RollableRef ) -> Html Msg
refResultsGroupView index ( firstRef, refs ) =
    case refs of
        [] ->
            refResultsSingleView index firstRef

        _ ->
            div
                [ class "ref-result-multiple" ]
                (mapChildIndexes index rollableRefView (firstRef :: refs))


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

        DidRoll _ _ ->
            -- TODO: replace at index
            ( model, Cmd.none )

        RollNew _ ->
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


rollOnTable : RollInstructions -> TableSource -> Generator TableRollResult
rollOnTable _ source =
    -- TODO: obey instructions for rollCount > 1 (TBD: row ranges, reroll, unique)
    pickRowFromTable source.rows


rollOnBundle : Bundle -> Generator Bundle
rollOnBundle bundle =
    List.map rollOnRef bundle.tables
        |> Random.Extra.sequence
        |> Random.map (\refs -> { bundle | tables = refs })


rollOnRef : RollableRef -> Generator RollableRef
rollOnRef r =
    case r of
        Ref ref ->
            case findTableSource aRegistry ref.path of
                Just table ->
                    -- TODO: multiple rolls on table
                    rollOnTable ref.instructions table
                        |> Random.map List.singleton
                        |> Random.map
                            (\res ->
                                RolledTable
                                    { path = ref.path
                                    , instructions = ref.instructions
                                    , result = res
                                    , title = table.title
                                    }
                            )

                _ ->
                    Random.constant r

        BundleRef ref ->
            rollOnBundle ref.bundle
                |> Random.map
                    (\res ->
                        BundleRef
                            { ref
                                | bundle = res
                            }
                    )

        _ ->
            Random.constant r
