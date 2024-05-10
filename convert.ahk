#Requires AutoHotkey v2.0
var := FileRead("data_in.txt")
Loop Parse var, "`n", "`r"
{
    if (RegExMatch(A_LoopField, "[0-9]{4}-[0-9]{2}-[0-9]{2}"))
    {
        var := A_LoopField
        var := RegExReplace(var, "[ \t]", " ")
        var := RegExReplace(var, "  ", " ")
        RegExMatch(var,"([0-9]{4}-[0-9]{2}-[0-9]{2}) (.*)(-[0-9]{1,},[0-9]{2}) PLN|([0-9]{4}-[0-9]{2}-[0-9]{2}) (.*)([0-9]{1,},[0-9]{2}) PLN", &field)
        field[1] != "" ? data := field[1] : data := field[4]
        field[2] != "" ? tytul := field[2] : tytul := field[5]
        field[3] != "" ? kwota := field[3] : kwota := field[6]
        FileAppend data . ";" . tytul . ";" . kwota . "`n", "data_out.csv"
    }
}

/*
RegExMatch(var,"^([0-9]{4}-[0-9]{2}-[0-9]{2});.*?;(.*?);(.*?);.*?;.*?;.*?;.*?;(.*?);.*?;(.*?);", &field)
        ;Kwota
        if (field[4] == "")
        {
            kwota := field[5]
        } else {
            kwota := field[4]
        }
        ;Tytuł transakcji jeżeli blik lub karta
        tytul1 := field[2]
        tytul1 := RegExReplace(tytul1, "^\s", "")
        tytul1 := RegExReplace(tytul1, "\s$", "")
        tytul1 := RegExReplace(tytul1, "  ", " ")
        If (RegExMatch(field[3], "blik|kartą|BLIK"))
        {
            tytul := tytul1
        } else {
            tytul2 := field[3]
            tytul2 := RegExReplace(tytul2, "^\s", "")
            tytul2 := RegExReplace(tytul2, "\s$", "")
            tytul := tytul1 . " " . tytul2
        }
        FileAppend field[1] . ";" . kwota . ";" . tytul . "`n", "convert.csv"
*/