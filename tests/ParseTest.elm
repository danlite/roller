module ParseTest exposing (..)

import Dice exposing (Expr(..), FormulaTerm(..))
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, int, intRange, list, string, tuple)
import Parse exposing (expression)
import Parser exposing (Parser)
import Random exposing (constant, maxInt)
import String exposing (fromInt)
import Test exposing (..)



-- Parsing helpers


parseExpression : String -> Result (List Parser.DeadEnd) Expr
parseExpression =
    Parser.run expression



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
        ]
