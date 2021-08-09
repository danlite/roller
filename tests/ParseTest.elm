module ParseTest exposing (..)

import Dice exposing (Expr(..), FormulaTerm(..), Range)
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, intRange, tuple)
import Parse exposing (ParsedRow, expression)
import Parser
import Random exposing (maxInt)
import String exposing (fromInt)
import Test exposing (..)



-- Parsing helpers


parseExpression : String -> Result (List Parser.DeadEnd) Expr
parseExpression =
    Parser.run expression


parseRow : String -> Result (List Parser.DeadEnd) ParsedRow
parseRow =
    Parser.run Parse.row



-- Fuzzers


positiveInt : Fuzzer Int
positiveInt =
    intRange 1 maxInt


nonNegativeInt : Fuzzer Int
nonNegativeInt =
    intRange 0 maxInt


fuzzyDice : Fuzzer ( Int, Int )
fuzzyDice =
    tuple ( positiveInt, positiveInt )



-- String helpers


inParentheses : String -> String
inParentheses content =
    "(" ++ content ++ ")"


diceString : Int -> Int -> String
diceString count sides =
    fromInt count ++ "d" ++ fromInt sides



-- Expression result helpers


diceExpr : Int -> Int -> Expr
diceExpr count sides =
    Term (MultiDie { count = count, sides = sides })


constantTerm : Int -> Expr
constantTerm n =
    Term (Constant n)


additionExpr : Int -> Int -> Expr
additionExpr n1 n2 =
    Add (Term (Constant n1)) (Term (Constant n2))


subtractionExpr : Int -> Int -> Expr
subtractionExpr n1 n2 =
    Sub (Term (Constant n1)) (Term (Constant n2))



-- Expectation helpers


expectParsedExpressionResult : Expr -> String -> Expectation
expectParsedExpressionResult expr input =
    Expect.equal
        (parseExpression input)
        (Ok expr)


expectParsedRowResult : Parse.ParsedRow -> String -> Expectation
expectParsedRowResult row input =
    Expect.equal
        (parseRow input)
        (Ok row)


suite : Test
suite =
    describe "The Parse module"
        [ describe "expressions"
            [ describe "simple math"
                [ fuzz nonNegativeInt
                    "constant value"
                    (\num ->
                        expectParsedExpressionResult
                            (constantTerm num)
                            (fromInt num)
                    )
                , fuzz nonNegativeInt
                    "constant value in parentheses"
                    (\num ->
                        expectParsedExpressionResult
                            (constantTerm num)
                            (inParentheses (fromInt num))
                    )
                , fuzz (tuple ( nonNegativeInt, nonNegativeInt ))
                    "constant addition"
                    (\( n1, n2 ) ->
                        expectParsedExpressionResult
                            (additionExpr n1 n2)
                            (fromInt n1 ++ " + " ++ fromInt n2)
                    )
                , fuzz (tuple ( nonNegativeInt, nonNegativeInt ))
                    "constant subtraction"
                    (\( n1, n2 ) ->
                        expectParsedExpressionResult
                            (subtractionExpr n1 n2)
                            (fromInt n1 ++ " - " ++ fromInt n2)
                    )
                ]
            , describe "dice"
                [ fuzz fuzzyDice
                    "multidie"
                    (\( count, sides ) ->
                        expectParsedExpressionResult
                            (diceExpr count sides)
                            (diceString count sides)
                    )
                , fuzz (tuple ( fuzzyDice, nonNegativeInt ))
                    "multidie with constant"
                    (\( ( count, sides ), num ) ->
                        expectParsedExpressionResult
                            (Add (diceExpr count sides) (constantTerm num))
                            (diceString count sides ++ "+" ++ fromInt num)
                    )
                ]
            ]
        , describe "rows"
            [ test "parses ranged row"
                (\_ ->
                    expectParsedRowResult
                        (Parse.RangedRow (Range 1 2) "My text")
                        "1-2|My text"
                )
            , test "parses single ranged row"
                (\_ ->
                    expectParsedRowResult
                        (Parse.RangedRow (Range 1 1) "My text")
                        "1|My text"
                )
            , test "parses simple row"
                (\_ ->
                    expectParsedRowResult
                        (Parse.SimpleRow "My text")
                        "My text"
                )
            , test "parses simple row that starts with a digit"
                (\_ ->
                    expectParsedRowResult
                        (Parse.SimpleRow "1 of my text")
                        "1 of my text"
                )
            ]
        , describe "rollable text"
            [ todo "parses rollable value (like [[@foo:2d6+1]])"
            , todo "parses percents"
            ]
        ]
