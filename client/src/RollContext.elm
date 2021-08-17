module RollContext exposing (..)

import Dice exposing (RolledValue(..), RowTextComponent(..))
import Dict exposing (Dict)
import IndexPath
import List.Extra
import Rollable exposing (Bundle, BundleRollResults(..), IndexPath, RollableRef(..), TableRollResult(..), onlyOneRollCount, tableRollResultsRefs)


type alias Context =
    ( Int, Dict String Int )


emptyContext : Context
emptyContext =
    ( 0, Dict.empty )


increaseDepth : Context -> Context
increaseDepth =
    Tuple.mapFirst ((+) 1)


depth : Context -> Int
depth =
    Tuple.first


addToContextFromRowTextComponent : RowTextComponent -> Context -> Context
addToContextFromRowTextComponent text context =
    case text of
        RollableText t ->
            case t.value of
                ValueResult v ->
                    context
                        |> (Dict.insert t.var v |> Tuple.mapSecond)

                _ ->
                    context

        _ ->
            context


addToContextFromResult : TableRollResult -> Context -> Context
addToContextFromResult result =
    case result of
        RolledRow row ->
            \context -> List.foldl addToContextFromRowTextComponent context row.result.text

        _ ->
            identity


addToContextFromResults : List TableRollResult -> Context -> Context
addToContextFromResults results context =
    List.foldl addToContextFromResult context results


addToContextFromRef : RollableRef -> Context -> Context
addToContextFromRef ref =
    case ref of
        RolledTable t ->
            addToContextFromResults t.result

        _ ->
            -- Debug.log "do not know how to merge context from a bundle" identity
            identity


contextFromRef : RollableRef -> Context
contextFromRef ref =
    addToContextFromRef ref emptyContext


refAtIndex : IndexPath -> Context -> List RollableRef -> Maybe ( Context, RollableRef )
refAtIndex index context model =
    case index of
        [] ->
            Nothing

        [ i ] ->
            List.Extra.getAt i model
                |> Maybe.map (\r -> ( addToContextFromRef r context, r ))

        i :: rest ->
            let
                ref =
                    List.Extra.getAt i model

                newContext =
                    case ref of
                        Just r ->
                            addToContextFromRef r context

                        _ ->
                            context
            in
            case ref of
                Just (BundleRef bundleRef) ->
                    case bundleRef.result of
                        UnrolledBundleRef ->
                            Nothing

                        RolledBundles bundles ->
                            case rest of
                                [ rolledBundleIndex ] ->
                                    List.Extra.getAt rolledBundleIndex bundles
                                        |> Maybe.map
                                            -- convert Bundle into BundleRef
                                            (\b ->
                                                ( newContext
                                                , BundleRef
                                                    { bundle = b
                                                    , path = bundleRef.path
                                                    , instructions = onlyOneRollCount bundleRef.instructions
                                                    , title = bundleRef.title
                                                    , result = UnrolledBundleRef
                                                    }
                                                )
                                            )

                                _ ->
                                    refAtIndexOfRolledBundles rest newContext bundles

                Just (RolledTable info) ->
                    case info.result of
                        [ rollResult ] ->
                            case rollResult of
                                RolledRow rolledRow ->
                                    refAtIndex rest newContext rolledRow.result.refs

                                _ ->
                                    Nothing

                        [] ->
                            Nothing

                        results ->
                            refAtIndexOfRolledTable rest newContext results

                _ ->
                    Nothing


refAtIndexOfRolledTable : IndexPath -> Context -> List TableRollResult -> Maybe ( Context, RollableRef )
refAtIndexOfRolledTable index context results =
    case index of
        _ :: _ ->
            tableRollResultsRefs results
                |> refAtIndex index context

        _ ->
            Nothing


refAtIndexOfRolledBundles : IndexPath -> Context -> List Bundle -> Maybe ( Context, RollableRef )
refAtIndexOfRolledBundles index context rolledBundles =
    case index of
        i :: rest ->
            List.Extra.getAt i rolledBundles
                |> Maybe.map .tables
                |> Maybe.andThen (refAtIndex rest context)

        _ ->
            Nothing
