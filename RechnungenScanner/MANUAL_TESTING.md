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
