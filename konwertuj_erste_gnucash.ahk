#Requires AutoHotkey v2.0
#SingleInstance Force

; Erste -> GnuCash CSV
; Wklej tekst transakcji w oknie i naciśnij przycisk „Generuj CSV”.
; Wynik zapisuje się jako gnucash.csv w folderze tego skryptu.

mainGui := Gui(, "Erste → GnuCash")
mainGui.SetFont("s10", "Segoe UI")
mainGui.AddText("xm w860", "Wklej skopiowany tekst transakcji z historii Erste:")
inputEdit := mainGui.AddEdit("xm w860 h460 Multi WantTab")
generateButton := mainGui.AddButton("xm w150 h34 Default", "Generuj CSV")
generateButton.OnEvent("Click", (*) => ConvertBankText(inputEdit.Value))
mainGui.Show("w900 h570")

ConvertBankText(source) {
    if (Trim(source) = "") {
        MsgBox("Wklej najpierw tekst transakcji do pola.", "Erste → GnuCash", "Icon!")
        return
    }

    rows := []
    rejectedCount := 0
    zeroAuthCount := 0
    outputLines := []

    for line in StrSplit(source, "`n") {
        line := RTrim(line, "`r")
        fields := ParseCsvLine(line, "`t")
        dateIndex := FindDateField(fields)
        if (!dateIndex)
            continue

        amountIndex := FindAmountField(fields, dateIndex)
        if (!amountIndex)
            continue

        statusText := ""
        for field in fields
            statusText .= " " . Trim(field)

        if InStr(statusText, "Odrzucona") {
            rejectedCount += 1
            continue
        }

        name := dateIndex < fields.Length ? Trim(fields[dateIndex + 1]) : ""
        detail := ""
        if (amountIndex > dateIndex + 1) {
            Loop (amountIndex - dateIndex - 2) {
                fieldIndex := dateIndex + A_Index + 1
                field := Trim(fields[fieldIndex])
                if (field != "" && !IsUiLabel(field))
                    detail .= (detail = "" ? "" : " ") . field
            }
        }

        amountCents := ParseAmount(fields[amountIndex])
        transactionText := name . " " . detail
        if (amountCents = 0 && InStr(StrLower(transactionText), "autoryzacja")) {
            zeroAuthCount += 1
            continue
        }

        description := MakeDescription(name, detail)
        if (description = "")
            description := "Transakcja bankowa"

        ; Średnik jest separatorem CSV, więc zastępujemy go przecinkiem w opisie.
        description := StrReplace(description, ";", ",")
        description := StrReplace(description, "`r", " ")
        description := StrReplace(description, "`n", " ")
        description := RegExReplace(description, "\s{2,}", " ")
        description := Trim(description)

        date := Trim(fields[dateIndex])
        outputLines.Push(date . ";" . description . ";" . FormatAmount(amountCents))
    }

    if (outputLines.Length = 0) {
        MsgBox("Nie znalazłem transakcji do zapisania. Plik gnucash.csv nie został zmieniony.", "Erste → GnuCash", "Icon!")
        return
    }

    outputPath := A_ScriptDir . "\gnucash.csv"
    outputText := JoinLines(outputLines, "`r`n") . "`r`n"

    try {
        if FileExist(outputPath)
            FileDelete(outputPath)
        FileAppend(outputText, outputPath, "UTF-8")
    } catch as err {
        MsgBox("Nie udało się zapisać pliku:`n" . outputPath . "`n`n" . err.Message, "Erste → GnuCash", "Iconx")
        return
    }

    MsgBox(
        "Zapisano " . outputLines.Length . " transakcji do:`n" . outputPath
        . (rejectedCount ? "`nPominięto odrzucone: " . rejectedCount : "")
        . (zeroAuthCount ? "`nPominięto autoryzacje 0,00 zł: " . zeroAuthCount : ""),
        "Erste → GnuCash",
        "Iconi"
    )
}

ParseCsvLine(line, delimiter := ";") {
    fields := []
    field := ""
    inQuotes := false
    i := 1
    length := StrLen(line)

    while (i <= length) {
        char := SubStr(line, i, 1)
        if (char = Chr(34)) {
            if (inQuotes && SubStr(line, i + 1, 1) = Chr(34)) {
                field .= Chr(34)
                i += 1
            } else {
                inQuotes := !inQuotes
            }
        } else if (char = delimiter && !inQuotes) {
            fields.Push(field)
            field := ""
        } else {
            field .= char
        }
        i += 1
    }

    fields.Push(field)
    return fields
}

FindDateField(fields) {
    for index, field in fields {
        if RegExMatch(Trim(field), "^\d{4}-\d{2}-\d{2}$")
            return index
    }
    return 0
}

FindAmountField(fields, dateIndex) {
    Loop fields.Length - dateIndex {
        index := dateIndex + A_Index
        if IsAmountField(fields[index])
            return index
    }
    return 0
}

IsAmountField(value) {
    value := NormalizeSpaces(Trim(value))
    return RegExMatch(value, "i)^[-+]?\d[\d ]*(?:[,.]\d{2})\s*(?:PLN)?$")
}

IsUiLabel(value) {
    value := Trim(value)
    return (value = "Więcej" || value = "Nowe zlecenie" || value = "Blokada" || value = "Odrzucona")
}

ParseAmount(value) {
    value := NormalizeSpaces(Trim(value))
    value := StrReplace(value, "PLN", "", false)
    value := Trim(value)

    negative := InStr(value, "-") = 1
    value := RegExReplace(value, "[^0-9,.]", "")
    parts := StrSplit(value, ",")
    if (parts.Length = 1)
        parts := StrSplit(value, ".")

    wholeText := RegExReplace(parts[1], "\D", "")
    fractionText := parts.Length > 1 ? RegExReplace(parts[2], "\D", "") : "00"
    fractionText := SubStr(fractionText . "00", 1, 2)
    whole := wholeText = "" ? 0 : Integer(wholeText)
    fraction := Integer(fractionText)
    cents := whole * 100 + fraction
    return negative ? -cents : cents
}

NormalizeSpaces(value) {
    value := StrReplace(value, Chr(160), " ")
    value := StrReplace(value, Chr(8239), " ")
    value := StrReplace(value, Chr(9), " ")
    return value
}

MakeDescription(name, detail) {
    name := Trim(name)
    detail := Trim(detail)

    if (detail != "") {
        ; Płatności kartą: usuń prefiks karty, typ operacji i jej kwotę z opisu.
        if RegExMatch(detail,
            "i)^(?:DOP\.\s*)?(?:MC|VISA)\s+[\d*]+\s+PŁATNOŚĆ(?:\s+KARTĄ)?\s+[\d.,]+\s*(?:PLN|EUR)\s*(?:1\s*EUR\s*=\s*[\d.,]+\s*PLN\s*)?(.+)$", &m) {
            detail := Trim(m[1])
        } else if RegExMatch(detail,
            "i)^(?:DOP\.\s*)?(?:MC|VISA)\s+[\d*]+\s+PRZELEW KARTĄ\s+[\d.,]+\s*(?:PLN|EUR)\s*(.+)$", &m) {
            detail := Trim(m[1])
        } else if RegExMatch(detail,
            "i)^karta\s+[\d*]+\s+PŁATNOŚĆ\s+(.+)$", &m) {
            detail := Trim(m[1])
        } else if RegExMatch(detail,
            "i)^(?:DOP\.\s*)?(?:MC|VISA)\s+[\d*]+\s+ZWROT PŁATNOŚCI KARTĄ\s+[\d.,]+\s*PLN\s+(.+)$", &m) {
            detail := "Zwrot płatności kartą " . Trim(m[1])
        } else if RegExMatch(detail, "i)^Zakup BLIK\s+(.+?)\s+ref:[\w-]+.*$", &m) {
            detail := Trim(m[1])
        }
    }

    name := CollapseRepeatedName(name)
    if (name = "")
        return detail
    if (detail = "")
        return name

    ; Bank często powtarza nazwę sprzedawcy w polu nazwy i szczegółach.
    if (StrLower(SubStr(detail, 1, StrLen(name))) = StrLower(name)) {
        tail := Trim(SubStr(detail, StrLen(name) + 1))
        if RegExMatch(tail, "i)^ref:[\w-]+.*$")
            tail := ""
        return name . (tail = "" ? "" : " " . tail)
    }

    return name . " " . detail
}

CollapseRepeatedName(name) {
    name := RegExReplace(Trim(name), "\s{2,}", " ")
    words := StrSplit(name, " ")
    if (words.Length < 2 || Mod(words.Length, 2) != 0)
        return name

    half := words.Length // 2
    first := ""
    second := ""
    Loop half {
        first .= (first = "" ? "" : " ") . words[A_Index]
        second .= (second = "" ? "" : " ") . words[half + A_Index]
    }
    return StrLower(first) = StrLower(second) ? first : name
}

FormatAmount(cents) {
    negative := cents < 0
    absolute := Abs(cents)
    whole := Floor(absolute / 100)
    fraction := Mod(absolute, 100)
    fractionText := fraction < 10 ? "0" . fraction : "" . fraction
    return (negative ? "-" : "") . whole . "," . fractionText
}

JoinLines(lines, separator) {
    text := ""
    for index, line in lines
        text .= (index = 1 ? "" : separator) . line
    return text
}


