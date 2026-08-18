# Manueller Testplan — RechnungenScanner Phase 1

Auf einem echten iPhone durchführen (Simulator hat keine Kamera).

## Einrichtung
- [x] App-Start ohne gespeichertes Token zeigt die Einstellungen-Ansicht
- [x] Ein SeaTable-Base-API-Token für die Base "Arztrechnungen" eintragen und speichern
- [x] Nach dem Speichern erscheint das Rechnungs-Board

## Scan-Flow
- [x] "+" öffnet die Kamera (VisionKit-Scanner)
- [x] Eine echte Arztrechnung fotografieren (Mehrseiten-Scan testen: 2 Seiten)
- [x] Nach dem Scan öffnet sich das Formular vorausgefüllt (Betrag/Rechnungsnummer, wo im Dokument vorhanden)
- [x] Vorbefüllte Werte vor dem Speichern korrigieren funktioniert
- [x] Neuen Arzt anlegen funktioniert und ist danach im Picker auswählbar
- [x] Nach "Speichern" erscheint die Karte sofort im Board mit "Wartet auf Sync"
- [x] Spätestens beim nächsten Wechsel in den Vordergrund (oder App-Neustart) verschwindet das Sync-Icon und der Eintrag ist in SeaTable sichtbar (inkl. hochgeladenem PDF)
- [x] Nach Pull-to-Refresh erscheint eine in SeaTable direkt angelegte Rechnung korrekt mit Arzt-Zuordnung und Status im Board (prüft, dass die Feldformate für Link-Spalten wirklich mit der echten API übereinstimmen — dies ist bisher nur gegen einen Mock getestet)

## Befund-Scan (optional bei Rechnungsanlage)
- [x] Im Formular gibt es einen Abschnitt "Befund" mit Button "Befund scannen"
- [x] "Befund scannen" öffnet erneut die Kamera; nach dem Scan zeigt der Abschnitt "Befund gescannt" statt des Buttons
- [x] "Entfernen" macht den Befund-Scan rückgängig, der Button "Befund scannen" erscheint wieder
- [x] Speichern ohne Befund-Scan funktioniert weiterhin wie bisher (kein Befund-Eintrag in SeaTable)
- [x] Speichern mit Befund-Scan legt nach dem Sync in SeaTable eine neue Zeile in der Tabelle "Befunde" an, mit hochgeladenem PDF in der Spalte "Befund" und Link zur zugehörigen Zeile in "Arztrechnungen"

## Einreichungs-Export
**Voraussetzung:** Die Tabelle `Arztrechnungen` in der SeaTable-Base braucht eine Spalte `Datum` vom Typ "Datum". Ohne diese Spalte schlägt das Anlegen/Synchronisieren jeder neuen Rechnung dauerhaft fehl (Outbox-Eintrag bleibt für immer hängen), und beim nächsten Pull-Refresh wird ein lokal erfasstes Datum stillschweigend wieder auf "kein Datum" zurückgesetzt.

- [ ] Im Formular für eine neue Rechnung lässt sich das Datum manuell setzen/korrigieren (DatePicker vorbefüllt mit OCR-Wert, falls erkannt)
- [ ] In den Einstellungen zeigt "Einreichungs-Ordner" zunächst "Nicht konfiguriert"
- [ ] "Ordner wählen" öffnet den System-Ordnerauswahl-Dialog; nach Auswahl eines Ordners (z. B. eines iCloud-Drive-Unterordners) zeigt die Einstellungen-Ansicht dessen Namen
- [ ] Nach App-Neustart bleibt der gewählte Ordner konfiguriert (Bookmark übersteht einen Neustart)
- [ ] In den Einstellungen unter "Patienten-Links" für einen Patienten einen ÖGK-Link und einen Merkur-Link eintragen; nach Verlassen der Ansicht und erneutem Öffnen sind beide Werte noch da
- [ ] Bei einer Rechnung mit Status "Offen" zeigt die Detailansicht einen Abschnitt "Einreichung" mit den Buttons "Für ÖGK vorbereiten", "Ordner öffnen" und "Bei ÖGK öffnen"
- [ ] "Für ÖGK vorbereiten" ohne konfigurierten Ordner zeigt eine Fehlermeldung, die auf die Einstellungen verweist
- [ ] Nach Konfiguration des Ordners: "Für ÖGK vorbereiten" legt `<Ordner>/<Jahr>/ÖGK/<Datum>_<Patient>_<Arzt>_<Betrag>EUR_Rechnung.pdf` an (und `..._Befund.pdf`, falls ein Befund gescannt wurde) und zeigt eine Erfolgsmeldung
- [ ] "Ordner öffnen" wechselt zur Dateien-App und zeigt den `ÖGK`-Unterordner mit der/den frisch abgelegten Datei(en)
- [ ] "Bei ÖGK öffnen" ist ausgeblendet, solange für den Patienten kein ÖGK-Link hinterlegt ist; nach Hinterlegen öffnet er Safari mit dem hinterlegten Link
- [ ] Direkt nach "Ordner öffnen" in Safari eine beliebige Upload-Seite öffnen und den System-Dateiauswahl-Dialog aufrufen: der zuvor geöffnete Ordner erscheint dort unter "Zuletzt"
- [ ] Rechnung auf Status "Krankenkasse abgeschlossen" ziehen: Detailansicht zeigt jetzt "Für Merkur vorbereiten" / "Bei Merkur öffnen" statt ÖGK, und der Export legt die Dateien unter `.../Merkur/` ab
- [ ] Rechnung auf einen Status ab "Merkur eingereicht" ziehen: der "Einreichung"-Abschnitt verschwindet komplett aus der Detailansicht

## Board & Statuswechsel
- [ ] Horizontales Scrollen zeigt die 6 Status-Spalten nebeneinander (mit Peek der nächsten Spalte)
- [ ] Eine Karte per Drag&Drop in die Nachbarspalte ziehen ändert den Status sofort lokal
- [ ] Der Statuswechsel ist nach Sync auch in SeaTable direkt sichtbar
- [ ] Tippen auf eine Karte öffnet die Detailansicht mit korrekten Werten
- [ ] Neuen Arzt beim Scannen anlegen funktioniert (Arzt-Zeile im Formular → Auswahl-Screen → "Anlegen")

## Offline-Verhalten
- [ ] Flugmodus aktivieren, neue Rechnung scannen und speichern → Karte erscheint mit Sync-Icon, kein Absturz
- [ ] Flugmodus deaktivieren → Eintrag synct automatisch (spätestens beim nächsten App-Vordergrund-Wechsel)
- [ ] Statuswechsel im Flugmodus verhält sich ebenso (optimistisches Update, späterer Sync)

## Fehlerfälle
- [ ] Über das Zahnrad-Symbol im Board-Toolbar zurück zu den Einstellungen navigieren, ein ungültiges Token eintragen → sinnvolle Fehlermeldung, keine Endlos-Ladeanimation
- [ ] Sync-Fehler (z. B. abgelaufenes Token) wird beim nächsten Öffnen des Einstellungen-Screens (Zahnrad-Symbol) angezeigt

## Bekannte Einschränkungen dieser Phase
- Nur Arztrechnungen + Arzt sind in der App bearbeitbar; alle anderen Tabellen bleiben SeaTable-only.
- Kein Multi-User-Login — ein gemeinsames API-Token für den Haushalt.
- "Server gewinnt" bei Konflikten — keine manuelle Konfliktauflösung in Phase 1.
