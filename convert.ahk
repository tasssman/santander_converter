#Requires AutoHotkey v2.0
var := FileRead("data_in.txt")
data_out := "data_out.csv"
if FileExist(data_out)
{
    FileDelete(data_out)
}

Loop Parse var, "`n", "`r"
{
    var_array := StrSplit(A_LoopField, ";")
    date := var_array[1]
    text := var_array[3]
    company := var_array[4]
    kwota := var_array[6]
    if(text ~= "DOP.")
    {
        text := RegExReplace(text,"DOP\..*PLN ","")
        FileAppend(date . ";" . text . ";" . kwota . "`n", data_out)
    } else if(text = "Płatność BLIK") {
        RegExReplace(text,"^.*transakcji [0-9]{1,} (.*)","",&text)

        FileAppend(date . ";" . company . " " . text[1] . ";" . kwota . "`n", data_out)
    } else {
        FileAppend(date . ";" . company . " " . text . ";" . kwota . "`n", data_out)
    }
}