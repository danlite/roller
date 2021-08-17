module ParseTest exposing (..)

import Dice
    exposing
        ( Expr(..)
        , FormulaTerm(..)
        , InputPlaceholderModifier(..)
        , Range
        , RolledPercent(..)
        , RolledValue(..)
        , RowTextComponent(..)
        )
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


expectParsedInputPlaceholderResult : RowTextComponent -> String -> Expectation
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
                , fuzz (tuple ( fuzzyDice, nonNegativeInt ))
                    "multidie with multiplier"
                    (\( ( count, sides ), num ) ->
                        expectParsedExpressionResult
                            (Mul (diceExpr count sides) (constantTerm num))
                            (diceString count sides ++ "*" ++ fromInt num)
                    )
                ]
            ]
        , describe "rows"
            [ test "parses ranged row"
                (\_ ->
                    expectParsedRowResult
                        (Parse.RangedRow (Range 1 2) [ PlainText "My text" ])
                        "1-2|My text"
                )
            , test "parses single ranged row"
                (\_ ->
                    expectParsedRowResult
                        (Parse.RangedRow (Range 1 1) [ PlainText "My text" ])
                        "1|My text"
                )
            , test "parses ranged row beginning with rollable value"
                (\_ ->
                    expectParsedRowResult
                        (Parse.RangedRow
                            (Range 1 1)
                            [ RollableText { expression = Term (MultiDie { count = 2, sides = 6 }), value = UnrolledValue, var = "a" }
                            , PlainText " My text"
                            ]
                        )
                        "1|[[@a:2d6]] My text"
                )
            , test "parses simple row"
                (\_ ->
                    expectParsedRowResult
                        (Parse.SimpleRow [ PlainText "My text" ])
                        "My text"
                )
            , test "parses simple row that starts with a digit"
                (\_ ->
                    expectParsedRowResult
                        (Parse.SimpleRow [ PlainText "1 of my text" ])
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
            , test "fails gracefully if rollable value is malformed"
                (\_ ->
                    let
                        malformed =
                            "[[dmg:4d8]]"
                    in
                    case
                        Parser.run Parse.rowText malformed
                    of
                        Err _ ->
                            Expect.pass

                        Ok _ ->
                            Expect.fail (malformed ++ "should be considered malformed")
                )
            , test "parses percent with % sign"
                (\_ ->
                    expectParsedRowTextResult
                        [ PlainText "Encounter either "
                        , PercentText { percent = 40, text = [ PlainText "foos (40%)" ], value = UnrolledPercent }
                        , PlainText " or "
                        , PercentText { percent = 60, text = [ PlainText "bars (60%)" ], value = UnrolledPercent }
                        ]
                        "Encounter either [[foos (40%)]] or [[bars (60%)]]"
                )
            , test "parses percent with \"percent\" term"
                (\_ ->
                    expectParsedRowTextResult
                        [ PlainText "Door "
                        , PercentText { percent = 75, text = [ PlainText "75 percent chance of being trapped" ], value = UnrolledPercent }
                        ]
                        "Door [[75 percent chance of being trapped]]"
                )
            , test "parses percent with nested rollable text"
                (\_ ->
                    expectParsedRowTextResult
                        [ PercentText
                            { percent = 50
                            , text = [ PlainText "one horse-sized duck (50%)" ]
                            , value = UnrolledPercent
                            }
                        , PlainText " or "
                        , PercentText
                            { percent = 50
                            , text =
                                [ RollableText { var = "horses", expression = diceExpr 4 8, value = UnrolledValue }
                                , PlainText " duck-sized horses (50%)"
                                ]
                            , value = UnrolledPercent
                            }
                        ]
                        "[[one horse-sized duck (50%)]] or [[[[@horses:4d8]] duck-sized horses (50%)]]"
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
                "parses comma separated components and rollable text"
                (\_ ->
                    expectParsedRowTextResult
                        [ PlainText "abc, "
                        , RollableText { var = "foo", expression = diceExpr 2 6, value = UnrolledValue }
                        , PlainText ", "
                        , InputPlaceholder "Def" []
                        , PlainText ", "
                        , InputPlaceholder "Ghi" []
                        ]
                        "abc, [[@foo:2d6]], [Def], [Ghi]"
                )
            , test
                "parses only input placeholder"
                (\_ ->
                    expectParsedRowTextResult
                        [ InputPlaceholder "OnlyName" []
                        ]
                        "[OnlyName]"
                )
            , test "parses input placeholder"
                (\_ ->
                    expectParsedInputPlaceholderResult
                        (InputPlaceholder "ModifiedName" [ InputPlaceholderColor "ab" ])
                        "[ModifiedName:c=ab]"
                )
            , test "parses input placeholder with nested []s"
                (\_ ->
                    expectParsedRowTextResult
                        [ InputPlaceholder "IndexedName" [ InputPlaceholderColor "a", InputPlaceholderIndex 2 ] ]
                        "[IndexedName:c=a:[2]]"
                )
            , test "parses input placeholder with alphanumeric variable"
                (\_ ->
                    expectParsedInputPlaceholderResult
                        (InputPlaceholder "Verb1" [])
                        "[Verb1]"
                )
            , test "parses multiple input placeholders"
                (\_ ->
                    expectParsedRowTextResult
                        [ InputPlaceholder "Noun1" []
                        , PlainText " "
                        , InputPlaceholder "Verb1" []
                        ]
                        "[Noun1] [Verb1]"
                )
            ]
        ]
