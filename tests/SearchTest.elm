module SearchTest exposing (..)

import Expect
import Search exposing (fuzzySearch)
import Test exposing (..)


expectFuzzyMatch : List String -> String -> String -> Expect.Expectation
expectFuzzyMatch terms input expected =
    Expect.equal (List.head (fuzzySearch terms input)) (Just expected)


suite : Test
suite =
    describe "The Search module"
        [ test "matches fuzzy 1"
            (\_ ->
                expectFuzzyMatch
                    [ "/a/b/c", "/d/e/f" ]
                    "abc"
                    "/a/b/c"
            )
        , test "matches fuzzy 2"
            (\_ ->
                expectFuzzyMatch
                    [ "/a/b/c", "/d/e/f" ]
                    "def"
                    "/d/e/f"
            )
        , test "favours matching initials"
            (\_ ->
                expectFuzzyMatch
                    [ "/abd/e/f", "/arguably/big/cat" ]
                    "a/b/c"
                    "/arguably/big/cat"
            )
        , test "doesn't favour matching initials TOO much"
            (\_ ->
                expectFuzzyMatch
                    [ "/i/like/dogfood", "/durable/ownership/goes/far/on/our/dev" ]
                    "dogfood"
                    "/i/like/dogfood"
            )
        , test "matches tavern"
            (\_ ->
                expectFuzzyMatch
                    [ "/dmg/adventures/twist", "/dmg/buildings/tavern" ]
                    "tavern"
                    "/dmg/buildings/tavern"
            )
        ]
