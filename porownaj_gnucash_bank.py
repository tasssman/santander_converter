# -*- coding: utf-8 -*-
"""Porównuje eksport GnuCash z historią bankową Erste (CSV, separator ;).
Wymaga wyłącznie Pythona 3 i standardowych bibliotek.
"""
import csv
import re
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path
from difflib import SequenceMatcher

@dataclass
class Tx:
    date: object
    amount: Decimal
    desc: str
    extra: str = ""
    status: str = ""
    source: int = 0


def money(value):
    if value is None:
        raise ValueError("brak kwoty")
    s = str(value).strip().replace("\u00a0", "").replace("\u202f", "").replace("PLN", "").replace(" ", "")
    if not s:
        raise ValueError("pusta kwota")
    # Bank może używać przecinka dziesiętnego; GnuCash zwykle tego samego formatu.
    if "," in s:
        s = s.replace(".", "").replace(",", ".")
    return Decimal(s).quantize(Decimal("0.01"))


def parse_date(s, formats):
    s = (s or "").strip()
    for fmt in formats:
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            pass
    raise ValueError("nieznana data: " + s)


def read_gnucash(path, account):
    rows, skipped = [], 0
    with open(path, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f, delimiter=";")
        headers = reader.fieldnames or []
        def col(*names):
            return next((n for n in names if n in headers), None)
        date_col = col("Data", "Date")
        amount_col = col("Amount Num.", "Kwota", "Amount")
        desc_col = col("Opis", "Description", "Memo")
        acct_col = col("Full Account Name", "Konto", "Account")
        status_col = col("Uzgodnij", "Reconcile")
        if not all((date_col, amount_col, desc_col, acct_col)):
            raise ValueError("Nie rozpoznaję kolumn pliku GnuCash. Oczekuję Data, Opis, Full Account Name i Amount Num.")
        for i, row in enumerate(reader, 2):
            if (row.get(acct_col) or "").strip() != account:
                continue
            try:
                rows.append(Tx(parse_date(row.get(date_col), ("%Y-%m-%d", "%d-%m-%Y", "%d.%m.%Y")), money(row.get(amount_col)), (row.get(desc_col) or "").strip(), status=(row.get(status_col) or "").strip() if status_col else "", source=i))
            except (ValueError, InvalidOperation):
                skipped += 1
    return rows, skipped


def read_bank(path):
    rows, skipped, meta = [], 0, []
    with open(path, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f, delimiter=";")
        for i, r in enumerate(reader, 1):
            # Format wejściowy santander_converter: data;opis;kwota
            # Nie ma osobnych daty operacji i księgowania ani salda.
            if len(r) == 3:
                try:
                    d = parse_date(r[0], ("%Y-%m-%d", "%d-%m-%Y", "%d.%m.%Y"))
                    rows.append(Tx(d, money(r[2]), r[1].strip(), source=i))
                except (ValueError, InvalidOperation):
                    skipped += 1
                continue
            if len(r) < 6:
                if r and any(x.strip() for x in r): meta.append(";".join(r))
                continue
            try:
                # Erste: data operacji, data księgowania, opis, nadawca/odbiorca, konto, kwota, saldo...
                d1 = parse_date(r[0], ("%Y-%m-%d", "%d-%m-%Y", "%d.%m.%Y"))
                d2 = parse_date(r[1], ("%Y-%m-%d", "%d-%m-%Y", "%d.%m.%Y"))
                amt = money(r[5])
                desc = " ".join(x.strip() for x in r[2:4] if x.strip())
                bal = ""
                if len(r) > 6 and r[6].strip():
                    try: bal = money(r[6])
                    except (ValueError, InvalidOperation): pass
                rows.append(Tx(d1, amt, desc, extra="data księgowania: " + d2.isoformat() + ("; saldo po operacji: " + str(bal) if bal else ""), source=i))
            except (ValueError, InvalidOperation):
                skipped += 1
    return rows, skipped, meta


def norm(s):
    return re.sub(r"[^a-z0-9ąćęłńóśźż]+", " ", (s or "").lower()).strip()


def match_rows(grows, brows, days):
    candidates = []
    for gi, g in enumerate(grows):
        for bi, b in enumerate(brows):
            if g.amount != b.amount:
                continue
            bank_dates = [b.date]
            m = re.search(r"data księgowania: (\d{4}-\d{2}-\d{2})", b.extra)
            if m: bank_dates.append(datetime.strptime(m.group(1), "%Y-%m-%d").date())
            delta = min(abs((g.date - bd).days) for bd in bank_dates)
            if delta <= days:
                sim = SequenceMatcher(None, norm(g.desc), norm(b.desc)).ratio()
                candidates.append((delta, -sim, gi, bi))
    candidates.sort()
    used_g, used_b, pairs = set(), set(), []
    for delta, negsim, gi, bi in candidates:
        if gi not in used_g and bi not in used_b:
            used_g.add(gi); used_b.add(bi); pairs.append((gi, bi, delta, -negsim))
    return pairs, [i for i in range(len(grows)) if i not in used_g], [i for i in range(len(brows)) if i not in used_b]


def fmt(v): return f"{v:,.2f}".replace(",", "X").replace(".", ",").replace("X", " ")
def txline(t): return f"{t.date.isoformat()} | {fmt(t.amount)} PLN | {t.desc}" + (f" | {t.extra}" if t.extra else "")


def make_report(grows, brows, pairs, gonly, bonly, gs, bs, bankmeta, days, gbal, bbal):
    lines = ["RAPORT PORÓWNANIA GnuCash – bank", "", f"Transakcje GnuCash na wybranym koncie: {len(grows)} (suma {fmt(sum((x.amount for x in grows), Decimal(0)))} PLN)", f"Transakcje bankowe: {len(brows)} (suma {fmt(sum((x.amount for x in brows), Decimal(0)))} PLN)", f"Dopasowano: {len(pairs)} | tolerancja dat: {days} dni", f"Pominięte wiersze: GnuCash {gs}, bank {bs}"]
    lines.append(f"Różnica sum przepływów (bank minus GnuCash): {fmt(sum((x.amount for x in brows), Decimal(0)) - sum((x.amount for x in grows), Decimal(0)))} PLN")
    if gbal is not None and bbal is not None:
        lines += [f"Saldo GnuCash: {fmt(gbal)} PLN", f"Saldo banku online: {fmt(bbal)} PLN", f"Różnica sald (bank minus GnuCash): {fmt(bbal-gbal)} PLN"]
    if bankmeta:
        lines += ["", "Informacja z pierwszego wiersza pliku bankowego:"] + ["  " + x for x in bankmeta]
    lines += ["", "DOPASOWANE (kwota zgodna, data w tolerancji)"]
    for gi, bi, delta, sim in sorted(pairs, key=lambda p: (grows[p[0]].date, grows[p[0]].desc)):
        lines.append(f"GnuCash: {txline(grows[gi])}")
        lines.append(f"Bank:    {txline(brows[bi])} (różnica dat {delta} dni)")
    lines += ["", "TYLKO W GnuCash — sprawdź, czy pozycja jest zdublowana, oczekująca lub poza zakresem wyciągu"]
    for i in gonly:
        t = grows[i]; lines.append(txline(t) + (f" | status uzgodnienia: {t.status}" if t.status else ""))
        near = [(abs((t.date-b.date).days), b) for b in brows if b.amount == t.amount]
        if near:
            d, b = min(near, key=lambda x:x[0]); lines.append(f"    Podobna kwota w banku, najbliższa data ({d} dni): {txline(b)}")
    lines += ["", "TYLKO W BANKU — sprawdź, czy nie brakuje wpisu w GnuCash"]
    lines += [txline(brows[i]) for i in bonly]
    lines += ["", "Uwaga: bankowy CSV zwykle zawiera zaksięgowane transakcje. Blokady/płatności oczekujące mogą występować tylko w bankowości online i nie muszą być błędami w GnuCash.", "Dopasowanie automatyczne opiera się na identycznej kwocie oraz dacie operacji lub księgowania; wszystkie pozycje z sekcji ‘tylko’ wymagają ręcznej oceny."]
    return "\n".join(lines)


class App(tk.Tk):
    def __init__(self):
        super().__init__(); self.title("Porównanie GnuCash i banku"); self.geometry("750x430"); self.minsize(650, 380)
        self.gpath=tk.StringVar(); self.bpath=tk.StringVar(); self.account=tk.StringVar(); self.days=tk.StringVar(value="3"); self.gbal=tk.StringVar(); self.bbal=tk.StringVar()
        self.grid_columnconfigure(1, weight=1)
        self.file_row(0, "Plik GnuCash CSV", self.gpath, self.pick_g)
        self.file_row(1, "Historia bankowa CSV", self.bpath, self.pick_b)
        ttk.Label(self,text="Konto GnuCash").grid(row=2,column=0,sticky="w",padx=8,pady=7)
        self.acct=ttk.Combobox(self,textvariable=self.account,width=65); self.acct.grid(row=2,column=1,columnspan=2,sticky="ew",padx=8,pady=7)
        ttk.Label(self,text="Tolerancja dat (dni)").grid(row=3,column=0,sticky="w",padx=8,pady=7); ttk.Entry(self,textvariable=self.days,width=10).grid(row=3,column=1,sticky="w",padx=8,pady=7)
        ttk.Label(self,text="Saldo GnuCash (opcjonalnie)").grid(row=4,column=0,sticky="w",padx=8,pady=7); ttk.Entry(self,textvariable=self.gbal,width=20).grid(row=4,column=1,sticky="w",padx=8,pady=7)
        ttk.Label(self,text="Saldo banku online (opcjonalnie)").grid(row=5,column=0,sticky="w",padx=8,pady=7); ttk.Entry(self,textvariable=self.bbal,width=20).grid(row=5,column=1,sticky="w",padx=8,pady=7)
        ttk.Button(self,text="Porównaj i zapisz raport…",command=self.run).grid(row=6,column=1,sticky="w",padx=8,pady=16)
        ttk.Label(self,text="Obsługuje pliki CSV z separatorem średnikowym. Salda wpisuj jako np. 11650,83.",wraplength=700).grid(row=7,column=0,columnspan=3,sticky="w",padx=8,pady=8)

    def file_row(self,row,label,var,command):
        ttk.Label(self,text=label).grid(row=row,column=0,sticky="w",padx=8,pady=7)
        ttk.Entry(self,textvariable=var).grid(row=row,column=1,sticky="ew",padx=8,pady=7)
        ttk.Button(self,text="Wybierz…",command=command).grid(row=row,column=2,padx=8,pady=7)
    def pick_g(self):
        p=filedialog.askopenfilename(title="Wybierz plik GnuCash",filetypes=[("CSV","*.csv"),("Wszystkie pliki","*.*")])
        if not p:return
        self.gpath.set(p)
        try:
            with open(p,"r",encoding="utf-8-sig",newline="") as f:
                rd=csv.DictReader(f,delimiter=";"); headers=rd.fieldnames or []; c="Full Account Name" if "Full Account Name" in headers else "Konto"
                vals=sorted({(r.get(c) or "").strip() for r in rd if (r.get(c) or "").strip()})
            self.acct["values"]=vals
            preferred=next((x for x in vals if "SAN Wspólne" in x), vals[0] if vals else "")
            self.account.set(preferred)
        except Exception as e: messagebox.showerror("Błąd pliku",str(e))
    def pick_b(self):
        p=filedialog.askopenfilename(title="Wybierz historię bankową",filetypes=[("CSV","*.csv"),("Wszystkie pliki","*.*")])
        if p:self.bpath.set(p)
    def run(self):
        try:
            if not self.gpath.get() or not self.bpath.get(): raise ValueError("Wybierz oba pliki CSV.")
            if not self.account.get(): raise ValueError("Wybierz konto GnuCash.")
            days=int(self.days.get())
            if days<0: raise ValueError("Tolerancja dat nie może być ujemna.")
            grows,gs=read_gnucash(self.gpath.get(),self.account.get()); brows,bs,meta=read_bank(self.bpath.get())
            if not grows: raise ValueError("Nie znaleziono transakcji dla wybranego konta.")
            pairs,gonly,bonly=match_rows(grows,brows,days)
            gbal=money(self.gbal.get()) if self.gbal.get().strip() else None; bbal=money(self.bbal.get()) if self.bbal.get().strip() else None
            report=make_report(grows,brows,pairs,gonly,bonly,gs,bs,meta,days,gbal,bbal)
            out=filedialog.asksaveasfilename(title="Zapisz raport",defaultextension=".txt",initialfile="raport_porownania.txt",filetypes=[("Raport tekstowy","*.txt"),("Wszystkie pliki","*.*")])
            if not out:return
            Path(out).write_text(report,encoding="utf-8-sig")
            messagebox.showinfo("Gotowe",f"Raport zapisano w pliku:\n{out}\n\nGnuCash tylko: {len(gonly)} | bank tylko: {len(bonly)}")
        except Exception as e: messagebox.showerror("Nie udało się porównać",str(e))

if __name__ == "__main__":
    App().mainloop()
