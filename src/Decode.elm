module Decode exposing (decoder, finalize)

import Dice
    exposing
        ( Expr(..)
        , FormulaTerm(..)
        , Range
        , makeSingleRange
        , rangeMembers
        )
import Dict exposing (Dict)
import Parse exposing (ParsedRow(..), row)
import Parser
import Rollable
    exposing
        ( RollInstructions
        , Rollable(..)
        , RollableRef(..)
        , RollableRefData
        , Row
        , UnresolvedRollableRefData
        , Variable(..)
        , resolvePathInContext
        )
import Yaml.Decode exposing (..)


listWrapDecoder : Decoder v -> Decoder (List v)
listWrapDecoder inner =
    oneOf
        [ list inner
        , map List.singleton inner
        , fail "listWrap"
        ]


variableDecoder : Decoder Variable
variableDecoder =
    oneOf
        [ map ConstValue int
        , map ContextKey string
        , fail "variable"
        ]


type RowIndexVariable
    = RowIndexConstValue Int
    | RowIndexRangeValue Range
    | RowIndexVariableValue String


decodeRange : Decoder Range
decodeRange =
    map (Parser.run Parse.parseRange) string
        |> andThen
            (\res ->
                case res of
                    Err e ->
                        fail ("Range parsing failed: " ++ Debug.toString e)

                    Ok r ->
                        case r of
                            Err e ->
                                fail ("Range parsing failed 2: " ++ Debug.toString e)

                            Ok range ->
                                succeed range
            )


rowIndexVariableDecoder : Decoder RowIndexVariable
rowIndexVariableDecoder =
    oneOf
        [ map RowIndexConstValue Yaml.Decode.int
        , map RowIndexRangeValue decodeRange
        , map RowIndexVariableValue string
        , fail "rowIndexVariable"
        ]


exprDecoder : Decoder Expr
exprDecoder =
    map (Parser.run Parse.expression) string
        |> andThen
            (\res ->
                case res of
                    Err e ->
                        fail ("Expression parsing failed: " ++ Debug.toString e)

                    Ok expr ->
                        succeed expr
            )


unresolvedTableRefDecoder : Decoder UnresolvedRollableRefData
unresolvedTableRefDecoder =
    succeed UnresolvedRollableRefData
        |> andMap (field "path" string)
        |> andMap rollInstructionsDecoder
        |> andMap (succeed Nothing)


resolveTableRef : String -> UnresolvedRollableRefData -> RollableRefData
resolveTableRef contextPath unresolved =
    RollableRefData
        (resolvePathInContext unresolved.path contextPath)
        unresolved.instructions
        unresolved.title


flattenRowIndexVariables : List RowIndexVariable -> List Variable
flattenRowIndexVariables rowVars =
    rowVars
        |> List.map
            (\riv ->
                case riv of
                    RowIndexConstValue c ->
                        [ ConstValue c ]

                    RowIndexVariableValue v ->
                        [ ContextKey v ]

                    RowIndexRangeValue r ->
                        rangeMembers r |> List.map ConstValue
            )
        |> List.concat


rollInstructionsDecoder : Decoder RollInstructions
rollInstructionsDecoder =
    succeed RollInstructions
        |> andMap (maybe (field "title" string))
        |> andMap (maybe (field "rollCount" variableDecoder))
        |> andMap (maybe (field "total" variableDecoder))
        |> andMap (maybe (field "dice" exprDecoder))
        |> andMap (oneOf [ field "unique" bool, succeed False, fail "unique" ])
        |> andMap
            (oneOf
                [ field "ignore" (listWrapDecoder rowIndexVariableDecoder)
                    |> map flattenRowIndexVariables
                , succeed []
                , fail "ignore"
                ]
            )
        |> andMap (maybe (field "modifier" variableDecoder))


type YamlRow
    = ContentRow ParsedRow
    | MetaRow UnresolvedRollableRefData


type alias YamlTableFields =
    { title : String
    , dice : Maybe Expr
    , rows : List YamlRow
    , inputs : Dict String UnresolvedRollableRefData
    , extraResults : Maybe String
    }


type alias YamlBundleFields =
    { title : String
    , tables : List UnresolvedRollableRefData
    }


type YamlFile
    = YamlTable YamlTableFields
    | YamlBundle YamlBundleFields


rowDecoder : Yaml.Decode.Decoder YamlRow
rowDecoder =
    oneOf
        [ map ContentRow
            (map
                (Parser.run row)
                string
                |> andThen parsedRowDecoder
            )
        , map MetaRow unresolvedTableRefDecoder
        , fail "row"
        ]


diceFromRowList : List a -> Expr
diceFromRowList rows =
    Term (MultiDie { count = 1, sides = List.length rows })


tableDecoder : Decoder YamlFile
tableDecoder =
    map5
        YamlTableFields
        (field "title" string)
        (maybe (field "dice" string)
            |> andThen
                (\maybeStr ->
                    case maybeStr of
                        Nothing ->
                            -- map diceFromRowList (field "rows" (list string))
                            succeed Nothing

                        Just str ->
                            case Parser.run Parse.expression str of
                                Err e ->
                                    fail ("Parsing dice failed: " ++ Debug.toString e)

                                Ok d ->
                                    succeed (Just d)
                )
        )
        (field "rows"
            (list rowDecoder)
        )
        (maybe (field "inputs" (dict unresolvedTableRefDecoder))
            |> andThen
                (\maybeDict ->
                    case maybeDict of
                        Nothing ->
                            succeed Dict.empty

                        Just dict ->
                            succeed dict
                )
        )
        (maybe (field "extraResults" string))
        |> map YamlTable


bundleDecoder : Decoder YamlFile
bundleDecoder =
    map2
        YamlBundleFields
        (field "title" string)
        (field "tables" (list unresolvedTableRefDecoder))
        |> map YamlBundle


decoder : Decoder YamlFile
decoder =
    oneOf [ tableDecoder, bundleDecoder, fail "decoder" ]


updateLastItem : (a -> a) -> List a -> List a
updateLastItem update aList =
    case List.reverse aList of
        [] ->
            []

        last :: remainder ->
            List.reverse (update last :: remainder)


addRollableRefToRow : RollableRef -> Row -> Row
addRollableRefToRow ref row =
    { row | refs = row.refs ++ [ ref ] }


addTableRefToLastRow : RollableRef -> List Row -> List Row
addTableRefToLastRow ref rows =
    updateLastItem (addRollableRefToRow ref) rows


finalizeRow : Int -> ParsedRow -> Row
finalizeRow rowNumber contentRow =
    case contentRow of
        SimpleRow content ->
            Row content (makeSingleRange rowNumber) []

        RangedRow range content ->
            Row content range []


gatherRows : String -> YamlRow -> ( Int, List Row ) -> ( Int, List Row )
gatherRows contextPath newRow ( rowCount, rows ) =
    case newRow of
        ContentRow contentRow ->
            let
                newRowCount =
                    rowCount + 1
            in
            ( newRowCount, rows ++ [ finalizeRow newRowCount contentRow ] )

        MetaRow tableRef ->
            ( rowCount, addTableRefToLastRow (resolveTableRef contextPath tableRef |> Ref) rows )


finalizeRows : String -> List YamlRow -> List Row
finalizeRows contextPath rows =
    Tuple.second (List.foldl (gatherRows contextPath) ( 0, [] ) rows)


finalize : String -> YamlFile -> Rollable
finalize path yamlFile =
    case yamlFile of
        YamlTable table ->
            let
                rows =
                    finalizeRows path table.rows
            in
            RollableTable
                { rows = rows
                , inputs = table.inputs |> Dict.map (\_ v -> resolveTableRef path v |> Ref)
                , path = path
                , title = table.title
                , dice =
                    case table.dice of
                        Just d ->
                            d

                        _ ->
                            diceFromRowList rows
                , extra = table.extraResults
                }

        YamlBundle bundle ->
            RollableBundle
                { path = path
                , tables = List.map (resolveTableRef path >> Ref) bundle.tables
                , title = bundle.title
                }


type alias RowParseResult =
    Result (List Parser.DeadEnd) ParsedRow


parsedRowDecoder : RowParseResult -> Yaml.Decode.Decoder ParsedRow
parsedRowDecoder parseResult =
    case parseResult of
        Err e ->
            fail ("Parsing row failed: " ++ Debug.toString e)

        Ok r ->
            succeed r
