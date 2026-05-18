#Requires AutoHotkey v2.0
var := FileRead("data_in.txt", "UTF-8")
data_out := "data_out.csv"
if FileExist(data_out)
{
    FileDelete(data_out)
}
var := RegExReplace(var, "Więcej")
var := RegExReplace(var, "[\t]", ";")
var := RegExReplace(var, "m)^;")


Loop Parse var, "`n", "`r"
{
    if(RegExMatch(A_LoopField,"[0-9]{4}-[0-9]{2}-[0-9]{2}") AND !RegExMatch(A_LoopField, "Odrzucona"))
    {
        var_array := StrSplit(A_LoopField, ";")
        date := var_array[1]
        company := var_array[2]
        tytul := var_array[3]
        price := var_array[4]

        if(tytul ~= "karta")
        {
            tytul := RegExReplace(tytul,"karta.*PŁATNOŚĆ ")
        } else if(tytul ~= "DOP") {
            tytul := RegExReplace(tytul,"DOP.* ")
        } else if(tytul ~= "BLIK") {
            tytul := RegExReplace(tytul,"Zakup.* ")
        }
        price := RegExReplace(price," PLN")
        FileAppend(date . ";" . company . " " . tytul . ";" . price . "`n", data_out,  "UTF-8")
    }
}