module RollableTest exposing (..)

import Expect
import Rollable exposing (Path(..), joinPaths, pathComponentRegex, refParentDir, replaceRegex, resolveDoubleDot, resolvePathInContext)
import Test exposing (..)


p : String -> Path
p =
    ResolvedPath


suite : Test
suite =
    describe "The Rollable module"
        [ describe "joinPaths"
            [ test "joins paths" (\_ -> Expect.equal (joinPaths "a" "b") "a/b")
            , test "joins paths 2" (\_ -> Expect.equal (joinPaths "/a/" "/b/") "/a/b/")
            , test "joins paths 3" (\_ -> Expect.equal (joinPaths "/a" "/b") "/a/b")
            , test "joins paths 4" (\_ -> Expect.equal (joinPaths "" "b") "/b")
            , test "joins paths 5" (\_ -> Expect.equal (joinPaths "/a/b/c" "../../f") "/a/b/c/../../f")
            ]
        , describe "refParentDir"
            [ test "refParentDir 1" (\_ -> refParentDir "/a/b/c" |> Expect.equal "/a/b")
            , test "refParentDir 2" (\_ -> refParentDir "/a/b" |> Expect.equal "/a")
            , test "refParentDir 3" (\_ -> refParentDir "/a" |> Expect.equal "/")
            , test "refParentDir 4" (\_ -> refParentDir "/" |> Expect.equal "/")
            ]
        , describe "resolvePathInContext"
            [ test "resolvePathInContext 1"
                (\_ ->
                    resolvePathInContext "a/b/c" "/d/e/f"
                        |> Expect.equal (p "/a/b/c")
                )
            , test "resolvePathInContext 2"
                (\_ ->
                    resolvePathInContext "./f" "/a/b/c"
                        |> Expect.equal (p "/a/b/f")
                )
            , test "resolvePathInContext 3"
                (\_ ->
                    resolvePathInContext "../f" "/a/b/c"
                        |> Expect.equal (p "/a/f")
                )
            , test "resolvePathInContext 4"
                (\_ ->
                    resolvePathInContext "../../f" "/a/b/c"
                        |> Expect.equal (p "/f")
                )
            ]
        , describe "relative path parsing"
            [ test "replaceRegex 1"
                (\_ ->
                    replaceRegex ("/" ++ pathComponentRegex ++ "/" ++ pathComponentRegex ++ "/\\.\\./") (always "/") "/abc/def/../a"
                        |> Expect.equal "/a"
                )
            , test "replaceRegex 2"
                (\_ ->
                    replaceRegex ("/" ++ pathComponentRegex ++ "/\\./") (always "/") "/abc/def/./a"
                        |> Expect.equal "/abc/a"
                )
            , test "resolveDoubleDot 1"
                (\_ ->
                    resolveDoubleDot "/a/b/../c"
                        |> Expect.equal "/a/c"
                )
            ]
        ]
