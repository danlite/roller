module Rollable exposing (..)

import Dice exposing (Expr, FormulaTerm(..), Range, RowTextComponent(..), rangeIncludes)
import Dict exposing (Dict)
import List.Extra exposing (getAt, setAt, updateAt)
import Maybe exposing (withDefault)
import Parse
import Parser
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


type alias Row =
    { text : String, range : Range, refs : List RollableRef }


type alias EvaluatedRow =
    { text : List RowTextComponent, refs : List RollableRef }


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
    = RolledRow { result : EvaluatedRow, rollTotal : Int, range : Range, inputs : Inputs }
    | MissingRowError { rollTotal : Int }


type alias TableSource =
    { rows : List Row
    , inputs : Dict String RollableRef
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


type alias Inputs =
    Dict String RollableRef


rolledInputsAsText : Inputs -> Dict String String
rolledInputsAsText =
    Dict.map (\_ v -> rolledRefAsText v)


rolledRefAsText : RollableRef -> String
rolledRefAsText ref =
    case ref of
        RolledTable table ->
            case List.head table.result of
                Just res ->
                    case res of
                        RolledRow row ->
                            plainRowText row.result.text

                        _ ->
                            "[???]"

                _ ->
                    "[???]"

        _ ->
            "[???]"


plainRowText : List RowTextComponent -> String
plainRowText =
    List.map
        (\rtc ->
            case rtc of
                PlainText t ->
                    t

                RollableText t ->
                    t.var

                InputPlaceholder t _ ->
                    t
        )
        >> String.join ""


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


rollResultForRollOnTable : List Row -> Inputs -> Int -> TableRollResult
rollResultForRollOnTable rows inputs rollTotal =
    case List.Extra.find (\r -> rangeIncludes rollTotal r.range) rows of
        Just row ->
            let
                rowText =
                    if String.startsWith ">- " row.text then
                        String.dropLeft 3 row.text

                    else
                        row.text
            in
            RolledRow
                { result =
                    EvaluatedRow
                        (Result.withDefault [ PlainText rowText ]
                            (Parser.run Parse.rowText rowText)
                        )
                        row.refs
                , rollTotal = rollTotal
                , range = row.range
                , inputs = inputs
                }

        _ ->
            MissingRowError { rollTotal = rollTotal }


tableRollResultsRefs : List TableRollResult -> List RollableRef
tableRollResultsRefs results =
    List.concatMap tableRollResultRefs results


tableRollResultRefs : TableRollResult -> List RollableRef
tableRollResultRefs result =
    case result of
        RolledRow r ->
            r.result.refs

        _ ->
            []


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
    case index of
        [] ->
            new

        _ ->
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
    let
        help : Int -> (RollableRef -> RollableRef) -> List TableRollResult
        help indexHead replacer =
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
                                    | result = replaceRefInRow indexHead curIndex replacer rr.result
                                }
                            )

                        _ ->
                            ( curIndex, res )
                )
                0
                results
                |> Tuple.second
    in
    case index of
        [] ->
            results

        [ i ] ->
            help i (always new)

        i :: rest ->
            help i (replaceNestedRef rest new)


replaceRefInRow : Int -> Int -> (RollableRef -> RollableRef) -> EvaluatedRow -> EvaluatedRow
replaceRefInRow targetIndex prevIndex update row =
    let
        rowLastIndex =
            prevIndex + List.length row.refs
    in
    if prevIndex <= targetIndex && targetIndex <= rowLastIndex then
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
