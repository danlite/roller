module ParseTest exposing (..)

import Dice exposing (Expr(..), FormulaTerm(..), Range, RolledValue(..), RowTextComponent(..))
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, intRange, tuple)
import Parse
import Parser
import Random exposing (maxInt)
import String exposing (fromInt)
import Test exposing (..)



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


diceExprWithConstant : Int -> Int -> Int -> Expr
diceExprWithConstant count sides const =
    Add
        (diceExpr count sides)
        (constantTerm const)


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


expectParseResult : Parser.Parser a -> a -> String -> Expectation
expectParseResult parser value input =
    Expect.equal
        (Parser.run parser input)
        (Ok value)


expectParsedExpressionResult : Expr -> String -> Expectation
expectParsedExpressionResult =
    expectParseResult Parse.expression


expectParsedRowResult : Parse.ParsedRow -> String -> Expectation
expectParsedRowResult =
    expectParseResult Parse.row


expectParsedRowTextResult : List RowTextComponent -> String -> Expectation
expectParsedRowTextResult =
    expectParseResult Parse.rowText


expectParsedInputPlaceholderResult =
    expectParseResult Parse.inputPlaceholder


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
        , describe "row text"
            [ test "parses rollable value (like [[@foo:2d6+1]])"
                (\_ ->
                    expectParsedRowTextResult
                        [ RollableText { var = "foo", expression = diceExprWithConstant 2 6 1, value = UnrolledValue } ]
                        "[[@foo:2d6+1]]"
                )
            , test "parses rollable value (like [[@foo:2d6]])"
                (\_ ->
                    expectParsedRowTextResult
                        [ RollableText { var = "foo", expression = diceExpr 2 6, value = UnrolledValue } ]
                        "[[@foo:2d6]]"
                )
            , test
                "parses plain text"
                (\_ ->
                    expectParsedRowTextResult [ PlainText "abc def" ] "abc def"
                )
            , test
                "parses plain and rollable text"
                (\_ ->
                    expectParsedRowTextResult
                        [ PlainText "abc "
                        , RollableText { var = "foo", expression = diceExpr 2 6, value = UnrolledValue }
                        , PlainText " def"
                        ]
                        "abc [[@foo:2d6]] def"
                )
            , test
                "parses only input placeholder"
                (\_ ->
                    expectParsedRowTextResult
                        [ InputPlaceholder "FirstName" {}
                        ]
                        "[FirstName]"
                )
            , test "parses input placeholder"
                (\_ ->
                    expectParsedInputPlaceholderResult
                        (InputPlaceholder "FirstName" {})
                        "[FirstName:feq2490@#]"
                )
            , todo "parses percents"
            ]
        ]
