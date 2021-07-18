module Parse exposing (..)

import Char exposing (isDigit)
import Dice exposing (Expr(..), FormulaTerm(..), Range, Row, makeRange, makeSingleRange)
import List.Extra exposing (find)
import Parser exposing ((|.), (|=), Parser, andThen, getChompedString, int, lazy, map, oneOf, spaces, succeed, symbol)
import String exposing (toInt)


type alias ParsedDice =
    { count : Int
    , sides : Int
    }


type ParsedRow
    = SimpleRow String
    | RangedRow Range String


parsedDiceToExpr : ParsedDice -> Expr
parsedDiceToExpr parsed =
    Term (parsedDiceToFormulaTerm parsed)


parsedDiceToFormulaTerm : ParsedDice -> FormulaTerm
parsedDiceToFormulaTerm parsed =
    MultiDie parsed


formulaTerm : Parser Expr
formulaTerm =
    oneOf
        [ succeed identity
            |. symbol "("
            |= lazy (\_ -> expression)
            |. symbol ")"
        , diceWithCount 1
        , succeed identity
            |= int
            |> andThen constantOrDiceWithSides
        ]


expression : Parser Expr
expression =
    formulaTerm
        |> andThen (expressionHelp [])


{-| Once you have parsed a term, you can start looking for `+` and \`\* operators.
I am tracking everything as a list, that way I can be sure to follow the order
of operations (PEMDAS) when building the final expression.
In one case, I need an operator and another term. If that happens I keep
looking for more. In the other case, I am done parsing, and I finalize the
expression.
-}
expressionHelp : List ( Expr, Operator ) -> Expr -> Parser Expr
expressionHelp revOps expr =
    oneOf
        [ succeed Tuple.pair
            |. spaces
            |= operator
            |. spaces
            |= formulaTerm
            |> andThen (\( op, newExpr ) -> expressionHelp (( expr, op ) :: revOps) newExpr)
        , lazy (\_ -> succeed (finalize revOps expr))
        ]


type Operator
    = AddOp
    | SubOp


operator : Parser Operator
operator =
    oneOf
        [ map (\_ -> AddOp) (symbol "+")
        , map (\_ -> SubOp) (symbol "-")
        ]


{-| We only have `+` and `*` in this parser. If we see a `MulOp` we can
immediately group those two expressions. If we see an `AddOp` we wait to group
until all the multiplies have been taken care of.
This code is kind of tricky, but it is a baseline for what you would need if
you wanted to add `/`, `-`, `==`, `&&`, etc. which bring in more complex
associativity and precedence rules.
-}
finalize : List ( Expr, Operator ) -> Expr -> Expr
finalize revOps finalExpr =
    case revOps of
        [] ->
            finalExpr

        -- ( expr, MulOp ) :: otherRevOps ->
        --     finalize otherRevOps (Mul expr finalExpr)
        ( expr, AddOp ) :: otherRevOps ->
            Add (finalize otherRevOps expr) finalExpr

        ( expr, SubOp ) :: otherRevOps ->
            Sub (finalize otherRevOps expr) finalExpr


{-| Parsing dice in the form "d20" (no leading integer)
-}
diceWithCount : Int -> Parser Expr
diceWithCount count =
    Parser.map parsedDiceToExpr
        (succeed (ParsedDice count)
            |. symbol "d"
            |= int
        )


{-| Try to continue parsing dice or use the chomped constant
-}
constantOrDiceWithSides : Int -> Parser Expr
constantOrDiceWithSides count =
    Parser.oneOf
        [ diceWithCount count
        , succeed (Term (Constant count))
        ]


type alias RangeParseResult =
    Result String Range


rangeMemberFromString : String -> Parser Int
rangeMemberFromString str =
    if str == "00" then
        Parser.succeed 100

    else
        case toInt str of
            Nothing ->
                Parser.problem "Could not parse integer in range"

            Just n ->
                Parser.succeed n


parseRangeMember : Parser Int
parseRangeMember =
    (Parser.getChompedString <|
        (succeed identity |= Parser.chompWhile isDigit)
    )
        |> Parser.andThen rangeMemberFromString


parseRange : Parser RangeParseResult
parseRange =
    Parser.oneOf
        [ succeed identity
            |= parseRangeMember
            |> andThen parseRangeEnd
        ]


rangeDivider : Parser ()
rangeDivider =
    Parser.oneOf
        [ symbol "-"
        , symbol "–"
        ]


parseRangeEnd : Int -> Parser RangeParseResult
parseRangeEnd start =
    Parser.oneOf
        [ succeed (makeRange start)
            |. rangeDivider
            |= parseRangeMember
        , succeed (Ok (makeSingleRange start))
        ]


rangeResultParser : RangeParseResult -> Parser Range
rangeResultParser result =
    case result of
        Err s ->
            Parser.problem ("Parsing range failed: " ++ s)

        Ok n ->
            Parser.succeed n


row : Parser ParsedRow
row =
    oneOf
        [ Parser.succeed RangedRow
            |= (parseRange
                    |> andThen rangeResultParser
               )
            |. symbol "|"
            |= (getChompedString <| succeed identity |= Parser.chompUntilEndOr "\n")
        , succeed SimpleRow
            |= (getChompedString <| succeed identity |= Parser.chompUntilEndOr "\n")
        ]
