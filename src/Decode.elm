module Decode exposing (..)

import Dice exposing (Expr(..), FormulaTerm(..), RegisteredRollable, Rollable(..), Row, Table, TableRef, Variable(..), makeSingleRange)
import Parse exposing (ParsedRow(..), expression, formulaTerm, row)
import Parser
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


tableRefDecoder : Decoder TableRef
tableRefDecoder =
    succeed TableRef
        |> andMap (field "path" string)
        |> andMap (maybe (field "title" string))
        |> andMap (maybe (field "rollCount" variableDecoder))
        |> andMap (maybe (field "total" variableDecoder))
        |> andMap (maybe (field "dice" exprDecoder))
        |> andMap (oneOf [ field "unique" bool, succeed False ])
        |> andMap (oneOf [ field "ignore" (listWrapDecoder variableDecoder), succeed [] ])
        |> andMap (maybe (field "modifier" variableDecoder))


type YamlRow
    = ContentRow ParsedRow
    | MetaRow TableRef


type alias YamlTableFields =
    { title : String
    , dice : Expr
    , rows : List YamlRow
    }


type alias YamlBundleFields =
    { title : String
    , tables : List TableRef
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


addTableRefToRow : TableRef -> Row -> Row
addTableRefToRow tableRef row =
    { row | tableRefs = row.tableRefs ++ [ tableRef ] }


addTableRefToLastRow : TableRef -> List Row -> List Row
addTableRefToLastRow tableRef rows =
    updateLastItem (addTableRefToRow tableRef) rows


finalizeRow : Int -> ParsedRow -> Row
finalizeRow rowNumber contentRow =
    case contentRow of
        SimpleRow content ->
            Row (makeSingleRange rowNumber) content []

        RangedRow range content ->
            Row range content []


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
            ( rowCount, addTableRefToLastRow tableRef rows )


finalizeRows : List YamlRow -> List Row
finalizeRows rows =
    Tuple.second (List.foldl gatherRows ( 0, [] ) rows)


finalize : String -> YamlFile -> RegisteredRollable
finalize path yamlFile =
    case yamlFile of
        YamlTable table ->
            RegisteredRollable
                path
                (RollableTable
                    (Table
                        (finalizeRows table.rows)
                        table.title
                        table.dice
                    )
                )

        YamlBundle bundle ->
            RegisteredRollable path (RollableBundle bundle)


type alias RowParseResult =
    Result (List Parser.DeadEnd) ParsedRow


parsedRowDecoder : RowParseResult -> Yaml.Decode.Decoder ParsedRow
parsedRowDecoder parseResult =
    case parseResult of
        Err e ->
            fail ("Parsing row failed: " ++ Debug.toString e)

        Ok r ->
            succeed r
