# Rechnungsscan: Prüfung der Feldererkennung anhand realer Arztrechnungen

Ergebnis der Prüfung aus Issue #14.

## Methodik

Ein lokales, nicht eingechecktes Testwerkzeug (`RechnungenKit` als Path-Dependency in ein
Scratch-Swift-Package eingebunden) hat `TextRecognizer` (Vision-OCR) und
`InvoiceFieldExtractor` aus `RechnungenKit/Sources/RechnungenKit/OCR/` gegen die realen
Rechnungen unter `Arztrechnungen/2025` und `Arztrechnungen/2026` laufen lassen (49
Rechnungs-Ordner, 141 PDF-Dateien). Der Ordner `Arztrechnungen/` liegt lokal im Projekt,
enthält personenbezogene Gesundheitsdaten und ist über `.gitignore` von Git ausgeschlossen –
er dient ausschließlich als lokale Testgrundlage.

Für jeden Rechnungs-Ordner wurde das plausibelste Rechnungsdokument ausgewählt (Priorität:
`Arztrechnung`/`Rechnung`/`Abrechnungsinformation`, bei Apotheken `Zahlungsbeleg` zuerst, da
dort die eigentliche Rechnung z. B. unter „Arztrechnung.pdf" tatsächlich das Rezept ist).
Beiliegende Zusatzdokumente (Befund, Leistungsbestätigung, Versicherungs-Korrespondenz,
Rezept) wurden nicht separat bewertet, da sie im Scan-Flow der App nicht als Rechnung
gescannt werden.

**Wichtiger Nebenbefund:** 10 der 49 Ordner enthalten Dateien mit `.pdf`-Endung, deren
tatsächlicher Inhalt ein JPEG/PNG ist (vermutlich Fotos, die beim Export aus einer anderen
App fälschlich als PDF benannt wurden). Diese ließen sich nicht rendern und wurden aus der
Trefferquote ausgeschlossen. Das betrifft nicht den echten Scan-Flow der App: Dieser erzeugt
über `VNDocumentCameraViewController` (`ScanService.swift`) immer valide PDFs, das Problem
existiert nur bei diesen manuell archivierten Dateien.

## Trefferquote (39 auswertbare Rechnungsdokumente)

| Feld | Vorher (naiver Codestand) | Nachher (nach Fixes unten) |
|---|---|---|
| Rechnungsnummer | 15/39 (38 %) | **17/39 (44 %)** |
| Betrag | 30/39 (77 %) | **39/39 (100 %)** |
| Rechnungsdatum | 37/39 (95 %) | **38/39 (97 %)** |

Auf dem vollen Rohbestand (141 Dateien, inkl. Befunde, Rezepte, Zahlungsbelege etc., die gar
keine Rechnungsnummer tragen müssen) lag die Rechnungsnummer-Erkennung anfangs bei nur 7/141 –
der mit Abstand größte Einzelbefund war, dass die meisten österreichischen
Wahlarzt-Honorarnoten das Feld gar nicht "Rechnungsnummer" nennen (siehe unten).

`Arzt` und `Patient` wurden **nicht** geprüft, weil `InvoiceFieldExtractor` diese Felder aktuell
gar nicht extrahiert – siehe „Bekannte Lücken" unten.

## Behobene systematische Fehler

Alle Fixes in `RechnungenKit/Sources/RechnungenKit/OCR/InvoiceFieldExtractor.swift`, mit
Regressionstests in `RechnungenKit/Tests/RechnungenKitTests/InvoiceFieldExtractorTests.swift`.

1. **"Honorarnote Nr." / "Honorarnotennr." nicht erkannt.** Die überwiegende Mehrheit der
   Wahlarzt-Honorarnoten in der Stichprobe beschriftet die Rechnungsnummer nicht mit
   "Rechnungsnummer", sondern mit "Honorarnote Nr." bzw. dem Kompositum "Honorarnotennr.".
   Das Extraktions-Regex kannte nur `Rechnungs(nummer|nr)`. → Label-Erkennung erweitert.
2. **"Re.Nr." und "Rechnungs-Nr" (mit Bindestrich) nicht erkannt.** Weitere, in der Stichprobe
   beobachtete Label-Varianten. → ergänzt.
3. **Von Vision durch Leerzeichen zerrissene Trennzeichen** (z. B. OCR liest "2025 / 108" statt
   "2025/108"). Der Wert wurde bisher am ersten Leerzeichen abgeschnitten. → Werte-Regex toleriert
   jetzt Leerzeichen um `/` und `-` und normalisiert sie weg.
4. **Rundbeträge mit "100,-" statt "100,00" wurden nicht als Betrag erkannt.** Auf
   österreichischen Rechnungen üblich. → zusätzliches Muster für `NNN,-`/`NNN.-`.
5. **Falscher Betrag, wenn ein früherer Positionspreis im Text vor der eigentlichen Summe
   steht** (konkret beobachtet: eine Rechnung listet zuerst "4 x 0,30" als Positionspreis,
   der bisherige "nimm den ersten Treffer"-Ansatz extrahierte fälschlich 0,30 statt der
   tatsächlichen Rechnungssumme). → der Betrag wird jetzt zuerst in der Nähe eines
   Summen-Labels ("Rechnungsbetrag", "Gesamtbetrag", "Endbetrag") gesucht, bevor auf den
   ersten Treffer auf der Seite zurückgefallen wird.

## Bekannte, nicht behobene Lücken (als Folge-Issues erfasst)

- **#15** – Apotheken-Kassabons tragen kein Rechnungsnummer-Label, nur eine interne
  "Belegnr./Genehmigungsnr."-Zeile; ob diese als Rechnungsnummer taugt, ist eine
  Produktentscheidung.
- **#16** – Vereinzelt steht die Nummer direkt hinter der Überschrift "HONORARNOTE" ganz ohne
  das Wort "Nr." (z. B. "HONORARNOTE 1/475/2026"); ein naiver Fix würde auf anderen Rechnungen
  Fließtext fälschlich als Nummer einfangen.
- **#17** – Datum wird bei Monatsnamen-Schreibweise ("19. Dez. 2025") und bei durch schlechten
  Druck OCR-seitig zusammengelaufenen, trennzeichenlosen Ziffernfolgen nicht erkannt.
- **#18** – Arzt und Patient werden aktuell überhaupt nicht aus dem OCR-Text vorbefüllt (kein
  Bug, sondern fehlende Funktionalität); Vorschlag: Fuzzy-Abgleich der OCR-Zeilen gegen die
  bestehende Provider-Liste.

## Nicht behandelt

Allgemeine OCR-Qualitätsschwankungen (verschluckte/verfälschte Zeichen bei schlecht
gedruckten oder kontrastarmen Originalen) sind eine inhärente Grenze jeder
kamerabasierten Texterkennung und wurden nicht als Parsing-Bug behandelt, sofern das
zugrundeliegende Label überhaupt korrekt erkannt wurde.
