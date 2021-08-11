module RollContext exposing (..)

import Dice exposing (RolledValue(..), RowTextComponent(..))
import Dict exposing (Dict)
import List.Extra
import Rollable exposing (IndexPath, RollContext, RollableRef(..), TableRollResult(..), tableRollResultsRefs)


type alias Context =
    ( Int, RollContext )


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
addToContextFromResult result context =
    case result of
        RolledRow row ->
            List.foldl addToContextFromRowTextComponent context row.result.text

        _ ->
            context


addToContextFromResults : List TableRollResult -> Context -> Context
addToContextFromResults results context =
    List.foldl addToContextFromResult context results


addToContextFromRef : RollableRef -> Context -> Context
addToContextFromRef ref context =
    context
        |> (case ref of
                RolledTable t ->
                    addToContextFromResults t.result

                _ ->
                    identity
           )


contextFromRef : RollableRef -> Context
contextFromRef ref =
    addToContextFromRef ref ( 0, Dict.empty )


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
            case List.Extra.getAt i model of
                Just (BundleRef bundleRef) ->
                    refAtIndex rest newContext bundleRef.bundle.tables

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
