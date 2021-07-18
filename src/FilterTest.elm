module FilterTest exposing (..)

import List.Extra


type alias Entry =
    { value : Int, enabled : Bool }


type alias Entries =
    List Entry


mainList : Entries
mainList =
    [ Entry 5 True
    , Entry 1 True
    , Entry 1 True
    , Entry 4 True
    , Entry 2 True
    , Entry 3 True
    ]


setEntryEnabled : Bool -> Entry -> Entry
setEntryEnabled enabled entry =
    { entry | enabled = enabled }


enableEntry : Entry -> Entry
enableEntry =
    setEntryEnabled True


disableEntry : Entry -> Entry
disableEntry =
    setEntryEnabled False


indexOfFirstEnabledMatchingEntry : Int -> Entries -> Maybe Int
indexOfFirstEnabledMatchingEntry targetValue entries =
    List.Extra.findIndex (\a -> a.value == targetValue && a.enabled == True) entries


disableFirstMatchingEntry : Int -> Entries -> Entries
disableFirstMatchingEntry targetValue entries =
    case indexOfFirstEnabledMatchingEntry targetValue entries of
        Nothing ->
            entries

        Just index ->
            List.Extra.updateAt index disableEntry entries



-- disable the two lowest entries in a list


disableTwoLowest : Entries -> Entries
disableTwoLowest entries =
    List.foldl disableFirstMatchingEntry entries (twoLowestValues entries)


twoLowestValues : Entries -> List Int
twoLowestValues entries =
    List.take 2 (List.map .value (List.sortBy .value entries))
