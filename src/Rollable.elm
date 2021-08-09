module Rollable exposing (..)

import Dice exposing (Expr, FormulaTerm(..), Range, rangeIncludes)
import Dict exposing (Dict)
import List.Extra exposing (getAt, setAt, updateAt)
import Maybe exposing (withDefault)
import Regex
import Result exposing (fromMaybe)


type DiceError
    = MissingContextVariable String
    | ValueNotMatchingRow Int


type Path
    = ResolvedPath String
    | RelativePathOutOfBounds String
    | InvalidRelativePath String String


type alias IndexPath =
    List Int


type RollableValue
    = RollableValue { var : String, expression : Expr }
    | RolledValue { var : String, expression : Expr, value : Int }


type RollableText
    = PlainText String
    | RollableText RollableValue


type alias Row =
    { text : String, range : Range, refs : List RollableRef }


type alias EvaluatedRow =
    { text : List RollableText, refs : List RollableRef }


type alias RollInstructions =
    { title : Maybe String
    , rollCount : Maybe Variable
    , total : Maybe Variable
    , dice : Maybe Expr
    , unique : Bool
    , ignore : List Variable
    , modifier : Maybe Variable

    --   store?: {
    --     [key: string]: '$roll'
    --   }
    }


emptyInstructions : RollInstructions
emptyInstructions =
    { title = Nothing
    , rollCount = Nothing
    , total = Nothing
    , dice = Nothing
    , unique = False
    , ignore = []
    , modifier = Nothing
    }


type alias UnresolvedRollableRefData =
    { path : String, instructions : RollInstructions, title : Maybe String }


type alias RollableRefData =
    { path : Path, instructions : RollInstructions, title : Maybe String }


type alias WithBundle a =
    { a | bundle : Bundle }


type alias WithTableResult a =
    { a | result : List TableRollResult, title : String }


type RollableRef
    = Ref RollableRefData
    | BundleRef (WithBundle RollableRefData)
    | RolledTable (WithTableResult RollableRefData)


updateBundle : WithBundle RollableRefData -> Bundle -> RollableRef
updateBundle original result =
    BundleRef { original | bundle = result }


simpleRef : String -> RollableRef
simpleRef path =
    Ref { path = ResolvedPath path, instructions = emptyInstructions, title = Nothing }


type TableRollResult
    = RolledRow { result : EvaluatedRow, rollTotal : Int, range : Range }
    | MissingRowError { rollTotal : Int }


type alias TableSource =
    { rows : List Row
    , inputs : List RollableRef
    , path : String
    , title : String
    , dice : Expr
    }


type alias Bundle =
    { path : String, title : String, tables : List RollableRef }


type Rollable
    = RollableTable TableSource
    | RollableBundle Bundle
    | MissingRollableError { path : String }


type alias Registry =
    Dict String Rollable


aRegistry : Registry
aRegistry =
    Dict.empty


pathString : Path -> String
pathString path =
    case path of
        ResolvedPath s ->
            s

        RelativePathOutOfBounds s ->
            "[OOB]" ++ s

        InvalidRelativePath s _ ->
            "[INV]" ++ s


joinPaths : String -> String -> String
joinPaths p1 p2 =
    p1 ++ "/" ++ p2 |> replaceRegex "/[/]+" (always "/")


pathComponents : String -> List String
pathComponents path =
    String.split "/" path
        |> List.filter (\c -> not <| c == "")


refParentDir : String -> String
refParentDir refPath =
    let
        components =
            pathComponents refPath
    in
    if List.length components < 1 then
        refPath

    else
        components
            -- drop the last segment
            |> List.reverse
            |> List.drop 1
            |> List.reverse
            |> String.join "/"
            -- prefix with /
            |> (++) "/"


replaceRegex : String -> (Regex.Match -> String) -> String -> String
replaceRegex userRegex replacer string =
    case Regex.fromString userRegex of
        Nothing ->
            Debug.log "bad regex" string

        Just regex ->
            Regex.replace regex replacer string


pathComponentRegex : String
pathComponentRegex =
    "([^./][^/]*)"


firstSubmatch : Regex.Match -> String
firstSubmatch match =
    List.head match.submatches
        |> Maybe.andThen identity
        |> withDefault match.match


resolvePathInContext : String -> String -> Path
resolvePathInContext path contextRefPath =
    if String.startsWith "$/" path then
        joinPaths contextRefPath path |> resolveDollarSign |> ResolvedPath

    else if String.startsWith "." path then
        joinPaths (refParentDir contextRefPath) path |> resolveRelativePaths

    else
        joinPaths "" path |> ResolvedPath


{-| The path before the "/../" is assumed to be a **folder**, not a ref.
-}
resolveDoubleDot : String -> String
resolveDoubleDot pathInContextDir =
    replaceRegex ("/" ++ pathComponentRegex ++ "/\\.\\./")
        (always "/")
        pathInContextDir


{-| The path before the "/./" is assumed to be a **folder**, not a ref.
-}
resolveSingleDot : String -> String
resolveSingleDot pathInContextDir =
    replaceRegex "/\\./"
        (always "/")
        pathInContextDir


{-| The path before the "/$/" is assumed to be a **ref**.
-}
resolveDollarSign : String -> String
resolveDollarSign pathInContextRef =
    replaceRegex "/\\$/"
        (always "/")
        pathInContextRef


resolveRelativePaths : String -> Path
resolveRelativePaths joinedPath =
    let
        resolvedPath =
            joinedPath
                |> resolveDoubleDot
                |> resolveSingleDot
                |> resolveDollarSign
    in
    if resolvedPath == joinedPath then
        ResolvedPath resolvedPath

    else
        resolveRelativePaths resolvedPath


findTableSource : Registry -> Path -> Maybe TableSource
findTableSource registry path =
    case path of
        ResolvedPath resolvedPath ->
            case Dict.get resolvedPath registry of
                Just (RollableTable data) ->
                    Just data

                _ ->
                    Nothing

        _ ->
            Nothing


findBundleSource : Registry -> Path -> Maybe Bundle
findBundleSource registry path =
    case path of
        ResolvedPath resolvedPath ->
            case Dict.get resolvedPath registry of
                Just (RollableBundle data) ->
                    Just data

                _ ->
                    Nothing

        _ ->
            Nothing


rollResultForRollOnTable : List Row -> Int -> TableRollResult
rollResultForRollOnTable rows rollTotal =
    case List.Extra.find (\r -> rangeIncludes rollTotal r.range) rows of
        Just row ->
            RolledRow { result = EvaluatedRow [ PlainText row.text ] row.refs, rollTotal = rollTotal, range = row.range }

        _ ->
            MissingRowError { rollTotal = rollTotal }


tableRollResultRefs : TableRollResult -> List RollableRef
tableRollResultRefs result =
    case result of
        RolledRow r ->
            r.result.refs

        _ ->
            []


refAtIndex : IndexPath -> List RollableRef -> Maybe RollableRef
refAtIndex index model =
    case index of
        [] ->
            Nothing

        [ i ] ->
            List.Extra.getAt i model

        i :: rest ->
            case List.Extra.getAt i model of
                Just (BundleRef bundleRef) ->
                    refAtIndex rest bundleRef.bundle.tables

                Just (RolledTable info) ->
                    case info.result of
                        [ rollResult ] ->
                            case rollResult of
                                RolledRow rolledRow ->
                                    refAtIndex rest rolledRow.result.refs

                                _ ->
                                    Nothing

                        _ ->
                            -- TODO: refer to mapAccuml in replaceAtIndexOfRolledTable
                            Debug.todo "lookup refAtIndex for a multiple-rolled-row table"

                _ ->
                    Nothing


replaceAtIndex : IndexPath -> RollableRef -> List RollableRef -> List RollableRef
replaceAtIndex index new list =
    case index of
        [] ->
            list

        [ i ] ->
            setAt i new list

        i :: rest ->
            updateAt i (replaceNestedRef rest new) list


replaceNestedRef : IndexPath -> RollableRef -> RollableRef -> RollableRef
replaceNestedRef index new old =
    case old of
        BundleRef info ->
            BundleRef
                { info
                    | bundle =
                        { path = info.bundle.path
                        , title = info.bundle.title
                        , tables = replaceAtIndex index new info.bundle.tables
                        }
                }

        RolledTable info ->
            RolledTable
                { info
                    | result =
                        replaceAtIndexOfRolledTable
                            index
                            new
                            info.result
                }

        _ ->
            old


replaceAtIndexOfRolledTable : IndexPath -> RollableRef -> List TableRollResult -> List TableRollResult
replaceAtIndexOfRolledTable index new results =
    case index of
        [] ->
            results

        [ i ] ->
            -- this gonna get messy
            -- TODO: refactor shared logic!
            List.Extra.mapAccuml
                (\curIndex res ->
                    case res of
                        RolledRow rr ->
                            let
                                newIndex =
                                    curIndex + List.length rr.result.refs
                            in
                            ( newIndex
                            , RolledRow
                                { rr
                                    | result = replaceRefInRow i curIndex (\_ -> new) rr.result
                                }
                            )

                        _ ->
                            ( curIndex, res )
                )
                0
                results
                |> Tuple.second

        i :: rest ->
            -- this gonna get messy
            -- TODO: refactor shared logic!
            List.Extra.mapAccuml
                (\curIndex res ->
                    case res of
                        RolledRow rr ->
                            let
                                newIndex =
                                    curIndex + List.length rr.result.refs
                            in
                            ( newIndex
                            , RolledRow
                                { rr
                                    | result = replaceRefInRow i curIndex (replaceNestedRef rest new) rr.result
                                }
                            )

                        _ ->
                            ( curIndex, res )
                )
                0
                results
                |> Tuple.second


replaceRefInRow : Int -> Int -> (RollableRef -> RollableRef) -> EvaluatedRow -> EvaluatedRow
replaceRefInRow targetIndex prevIndex update row =
    let
        rowLastIndex =
            prevIndex + List.length row.refs
    in
    if prevIndex <= targetIndex && targetIndex <= rowLastIndex then
        -- do the thing
        let
            relIndex =
                targetIndex - prevIndex
        in
        case getAt relIndex row.refs of
            Just existingRow ->
                EvaluatedRow row.text <| setAt (targetIndex - prevIndex) (update existingRow) row.refs

            Nothing ->
                row

    else
        row


tableMin : TableSource -> Maybe Int
tableMin table =
    List.minimum (List.map (\r -> r.range.min) table.rows)


tableMax : TableSource -> Maybe Int
tableMax table =
    List.maximum (List.map (\r -> r.range.max) table.rows)


tableSize : TableSource -> Int
tableSize table =
    case tableMax table of
        Nothing ->
            0

        Just max ->
            case tableMin table of
                Nothing ->
                    0

                Just min ->
                    max - min


dieForTable : TableSource -> FormulaTerm
dieForTable table =
    MultiDie { count = 1, sides = tableSize table }


type Variable
    = ConstValue Int
    | ContextKey String


type alias RollContext =
    Dict String Int


type alias ContextVariableResult =
    Result DiceError Int


valueInContext : Variable -> RollContext -> ContextVariableResult
valueInContext var context =
    case var of
        ConstValue n ->
            Ok n

        ContextKey k ->
            fromMaybe (MissingContextVariable k) (Dict.get k context)


rollCount : Maybe Variable -> RollContext -> ContextVariableResult
rollCount var context =
    withDefault
        (Ok 1)
        (Maybe.map (\v -> valueInContext v context) var)
