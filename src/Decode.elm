module Decode exposing (..)

import Dice exposing (Expr(..), FormulaTerm(..), Row, Table, TableRef, Variable(..), makeSingleRange)
import Parse exposing (ParsedRow(..), expression, formulaTerm, row)
import Parser
import Yaml.Decode exposing (Decoder, Error, andMap, andThen, bool, fail, field, list, map, map3, map4, maybe, oneOf, string, succeed)


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


type alias YamlTable =
    { path : String
    , title : String
    , dice : Expr
    , rows : List YamlRow
    }


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


decoder : String -> Yaml.Decode.Decoder YamlTable
decoder path =
    map4
        YamlTable
        (succeed path)
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


finalize : YamlTable -> Table
finalize table =
    Table
        table.path
        (finalizeRows table.rows)
        table.title
        table.dice


type alias RowParseResult =
    Result (List Parser.DeadEnd) ParsedRow


parsedRowDecoder : RowParseResult -> Yaml.Decode.Decoder ParsedRow
parsedRowDecoder parseResult =
    case parseResult of
        Err e ->
            fail ("Parsing row failed: " ++ Debug.toString e)

        Ok r ->
            succeed r


yamlTable : String
yamlTable =
    """
title: Potion Miscibility
dice: d100
rows:
  - 01|The mixture creates a magical explosion, dealing 6d10 force damage to the mixer and 1d10 force damage to each creature within 5 feet of the mixer.
  - something: 3
    path: ./somewhere
    title: Some cool title
    count: 2

  - 02–08|The mixture becomes an ingested poison of the DM’s choice.
  - 09–15|Both potions lose their effects.
  - 16–25|One potion loses its effect.
  - 26–35|Both potions work, but with their numerical effects and durations halved. A potion has no effect if it can’t be halved in this way.
  - 36–90|Both potions work normally.
  - 91–99|The numerical effects and duration of one potion are doubled. If neither potion has anything to double in this way, they work normally.
  - 00|Only one potion works, but its effect is permanent. Choose the simplest effect to make permanent, or the one that seems the most fun. For example, a potion of healing might increase the drinker’s hit point maximum by 4, or oil of etherealness might permanently trap the user in the Ethereal Plane. At your discretion, an appropriate spell, such as dispel magic or remove curse, might end this lasting effect.
"""


myTable : Result Error Table
myTable =
    Yaml.Decode.fromString (map finalize (decoder "/myTable")) yamlTable
