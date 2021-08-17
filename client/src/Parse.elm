module Parse exposing (..)

import Char exposing (isDigit)
import Dice
    exposing
        ( Expr(..)
        , FormulaTerm(..)
        , InputPlaceholderModifier(..)
        , Range
        , RollablePercent
        , RolledPercent(..)
        , RolledValue(..)
        , RowTextComponent(..)
        , makeRange
        , makeSingleRange
        )
import Parser exposing (..)
import Set
import String exposing (toInt)


type alias ParsedDice =
    { count : Int
    , sides : Int
    }


type ParsedRow
    = SimpleRow (List RowTextComponent)
    | RangedRow Range (List RowTextComponent)


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
        , succeed
            (negate >> Constant >> Term)
            |. symbol "-"
            |= int
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
    | MulOp


operator : Parser Operator
operator =
    oneOf
        [ map (\_ -> AddOp) (symbol "+")
        , map (\_ -> SubOp) (symbol "-")
        , map (\_ -> MulOp) (symbol "*")
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

        ( expr, MulOp ) :: otherRevOps ->
            finalize otherRevOps (Mul expr finalExpr)

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
    succeed identity
        |= parseRangeMember
        |> andThen parseRangeEnd


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


rangedRowParser : Parser ParsedRow
rangedRowParser =
    succeed RangedRow
        -- fails here if it's a plain text row beginning with a digit!
        |= (parseRange
                |> andThen rangeResultParser
           )
        |. symbol "|"
        |= rowText


row : Parser ParsedRow
row =
    oneOf
        [ backtrackable rangedRowParser
        , succeed SimpleRow
            |= rowText
        ]


rollableVar : Parser String
rollableVar =
    variable
        { start = Char.isAlpha
        , inner = \c -> Char.isAlphaNum c || c == '-'
        , reserved = Set.empty
        }


rollableValue : Parser RowTextComponent
rollableValue =
    succeed (\var ex -> { var = var, expression = ex, value = UnrolledValue })
        |. symbol "[[@"
        |= rollableVar
        |. symbol ":"
        |= expression
        |. symbol "]]"
        |> map RollableText


plainText : Parser RowTextComponent
plainText =
    succeed PlainText
        |= plainTextHelp


plainTextHelp : Parser String
plainTextHelp =
    getChompedString <|
        succeed ()
            |. chompUntilEndOr "["


inputPlaceholder : Parser RowTextComponent
inputPlaceholder =
    oneOf
        [ backtrackable <|
            succeed InputPlaceholder
                |. symbol "["
                |= variable { start = Char.isAlpha, inner = \c -> Char.isAlphaNum c || (c == '-'), reserved = Set.empty }
                |= ipModifiers

        -- We might be dealing with some plain text with brackets [like this],
        -- in which case we can backtrack out of the InputPlaceholder and
        -- parse the plain text, manually prepending the opening bracket
        , succeed (\bracket rest -> PlainText (bracket ++ rest))
            |= (chompIf ((==) '[') |> getChompedString)
            |= plainTextHelp
        ]


ipVariableValue : Parser String
ipVariableValue =
    variable { start = Char.isAlpha, inner = Char.isAlpha, reserved = Set.empty }


ipModifier : Parser InputPlaceholderModifier
ipModifier =
    oneOf
        [ succeed InputPlaceholderIndex
            |. symbol ":["
            |= int
            |. symbol "]"
        , succeed identity
            |. symbol ":"
            |= oneOf
                [ ipVariablePair InputPlaceholderColor (keyword "c") ipVariableValue
                , ipVariablePair InputPlaceholderBackgroundColor (keyword "cbg") ipVariableValue
                , ipVariablePair InputPlaceholderTextTransform (keyword "t") ipVariableValue
                ]
        ]


ipVariablePair : (String -> InputPlaceholderModifier) -> Parser () -> Parser String -> Parser InputPlaceholderModifier
ipVariablePair mod varName varValue =
    succeed mod
        |. varName
        |. symbol "="
        |= varValue


ipModifiers : Parser (List InputPlaceholderModifier)
ipModifiers =
    loop [] ipModifiersHelp


ipModifiersHelp : List InputPlaceholderModifier -> Parser (Step (List InputPlaceholderModifier) (List InputPlaceholderModifier))
ipModifiersHelp modifiers =
    oneOf
        [ symbol "]"
            |> map (\_ -> Done (List.reverse modifiers))
        , succeed (\modifier -> Loop (modifier :: modifiers))
            |= ipModifier
        ]


percentText : Parser RowTextComponent
percentText =
    succeed (\( text, value ) -> PercentText <| RollablePercent text value UnrolledPercent)
        |. symbol "[["
        |= (percentTextValue
                |> mapChompedString
                    (\s value ->
                        case Parser.run rowText s of
                            Ok rtcs ->
                                ( rtcs, value )

                            Err _ ->
                                ( [], value )
                    )
           )
        |. symbol "]]"


percentTextValue : Parser Int
percentTextValue =
    succeed identity
        |. chompWhile (not << Char.isDigit)
        |= oneOf
            [ backtrackable <|
                succeed identity
                    |= int
                    |. oneOf [ symbol "%", keyword " percent" ]
            , backtrackable <| (int |> andThen (\_ -> percentTextValue))
            ]
        |. chompUntil "]]"


rollableText : Parser RowTextComponent
rollableText =
    oneOf
        [ rollableValue
        , percentText
        , inputPlaceholder
        , plainText
        ]


rowText : Parser (List RowTextComponent)
rowText =
    succeed identity
        |. oneOf [ symbol ">- ", succeed () ]
        |= loop
            []
            rowTextHelp


rowTextHelp : List RowTextComponent -> Parser (Step (List RowTextComponent) (List RowTextComponent))
rowTextHelp revParts =
    oneOf
        [ oneOf [ symbol "\n", end ] |> map (\_ -> Done (List.reverse revParts))
        , succeed (\part -> Loop (part :: revParts))
            |= rollableText
        ]
