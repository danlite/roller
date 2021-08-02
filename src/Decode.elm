module Decode exposing (..)

import Dice
    exposing
        ( Expr(..)
        , FormulaTerm(..)
        , makeSingleRange
        )
import Parse exposing (ParsedRow(..), expression, formulaTerm, row)
import Parser
import V2.Rollable exposing (RollInstructions, Rollable(..), RollableRef(..), RollableRefData, Row, TableSource, Variable(..))
import Yaml.Decode exposing (Decoder, andMap, andThen, bool, fail, field, list, map, map2, map3, maybe, oneOf, string, succeed)


listWrapDecoder : Decoder v -> Decoder (List v)
listWrapDecoder inner =
    oneOf
        [ list inner
        , map List.singleton inner
        ]


variableDecoder : Decoder Variable
variableDecoder =
    oneOf
        [ map ConstValue Yaml.Decode.int
        , map ContextKey string
        ]


exprDecoder : Decoder Expr
exprDecoder =
    map (Parser.run formulaTerm) string
        |> andThen
            (\res ->
                case res of
                    Err e ->
                        fail ("Expression parsing failed: " ++ Debug.toString e)

                    Ok expr ->
                        succeed expr
            )


tableRefDecoder : Decoder RollableRefData
tableRefDecoder =
    succeed RollableRefData
        |> andMap (field "path" string)
        |> andMap rollInstructionsDecoder
        |> andMap (succeed Nothing)


rollInstructionsDecoder : Decoder RollInstructions
rollInstructionsDecoder =
    succeed RollInstructions
        |> andMap (maybe (field "title" string))
        |> andMap (maybe (field "rollCount" variableDecoder))
        |> andMap (maybe (field "total" variableDecoder))
        |> andMap (maybe (field "dice" exprDecoder))
        |> andMap (oneOf [ field "unique" bool, succeed False ])
        |> andMap (oneOf [ field "ignore" (listWrapDecoder variableDecoder), succeed [] ])
        |> andMap (maybe (field "modifier" variableDecoder))


type YamlRow
    = ContentRow ParsedRow
    | MetaRow RollableRefData


type alias YamlTableFields =
    { title : String
    , dice : Expr
    , rows : List YamlRow
    }


type alias YamlBundleFields =
    { title : String
    , tables : List RollableRefData
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
        , map MetaRow tableRefDecoder
        ]


diceFromRowList : List a -> Expr
diceFromRowList rows =
    Term (MultiDie { count = 1, sides = List.length rows })


tableDecoder : Decoder YamlFile
tableDecoder =
    map3
        YamlTableFields
        (field "title" string)
        (maybe (field "dice" string)
            |> andThen
                (\maybeStr ->
                    case maybeStr of
                        Nothing ->
                            map diceFromRowList (field "rows" (list string))

                        Just str ->
                            case Parser.run expression str of
                                Err e ->
                                    fail ("Parsing dice failed: " ++ Debug.toString e)

                                Ok d ->
                                    succeed d
                )
        )
        (field "rows"
            (list rowDecoder)
        )
        |> map YamlTable


bundleDecoder : Decoder YamlFile
bundleDecoder =
    map2
        YamlBundleFields
        (field "title" string)
        (field "tables" (list tableRefDecoder))
        |> map YamlBundle


decoder : Decoder YamlFile
decoder =
    oneOf [ tableDecoder, bundleDecoder ]


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


gatherRows : YamlRow -> ( Int, List Row ) -> ( Int, List Row )
gatherRows newRow ( rowCount, rows ) =
    case newRow of
        ContentRow contentRow ->
            let
                newRowCount =
                    rowCount + 1
            in
            ( newRowCount, rows ++ [ finalizeRow newRowCount contentRow ] )

        MetaRow tableRef ->
            ( rowCount, addTableRefToLastRow (Ref tableRef) rows )


finalizeRows : List YamlRow -> List Row
finalizeRows rows =
    Tuple.second (List.foldl gatherRows ( 0, [] ) rows)


finalize : String -> YamlFile -> Rollable
finalize path yamlFile =
    case yamlFile of
        YamlTable table ->
            RollableTable
                { rows = finalizeRows table.rows
                , inputs = []
                , path = path
                , title = table.title
                , dice = table.dice
                }

        YamlBundle bundle ->
            RollableBundle
                { path = path
                , tables = List.map Ref bundle.tables
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
