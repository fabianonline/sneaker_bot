# sneaker_bot
erstellt von Fabian Schlenz | [twitter.com/fabianonline](https://twitter.com/fabianonline)

## Einleitung
sneaker_bot wurde erstellt, um per Twitter zu ermitteln wer an der wöchentlichen Sneak Preview teilnehemn wird.

## Funktionen
- Komplett über Twitter steuerbar
- Speichert Anwesenheit/Abwesenhenheit der Nutzer inklusive "Prä-Sneak-Programm" (PSP)-Flag
- Möglichkeit Gäste anzukündigen, die keinen Twitter-Account besitzen
- Verwaltung von Bonuskarten und Reservierungen
- Automatische Anlage einer neuen Sneak nach einem konfigurierbaren Zeitplan
- Ausgabe der Teilnehmer per Twitter und per Webmodul (Webmodul mit Historie)
- Erinnerung vorheriger Teilnehmer, die sich noch nicht geäußert haben, ob sie teilnehmen
- Jeder Nutzer kann eine Standard-Antwort hinterlegen

## Installation
1. `bundle install`
2. Aus der `config.example.yml` eine `config.yml` erstellen
3. `bundle exec ruby create_db.rb` oder `bundle exec ruby -r './sneaker_bot.core.rb' -e 'DataMapper.auto_upgrade!'` ausführen
4. Per `bundle exec ruby -r './sneaker_bot.core.rb' -e 'SneakerBot.console'` einen Admin-User anlegen
5. Einen Cron-Job für `bundle exec ruby -r './sneaker_bot.core.rb' -e 'SneakerBot.cron'` einrichten

## Rechteverwaltung
Für jeden, der den sneaker_bot snchreibt, wird automatisch ein Eintrag in der Tabelle `users` angelegt. Dort kann ein Eintrag auf admin = 1 oder 0 gesetzt werden, um Zugang zu Administrationsfunktionen zu gewähren oder zu entziehen.
Automatisch angelegte Nutzer haben keinen Zugriff auf Administrationsfunktionen.

Müssen manuell Nutzer in die Tabelle `users` eingetragen werden, reicht es entweder username oder twitter_id auf einen sinnvollen Wert zu setzen; der jeweils andere Wert wird bei der Verarbeitung des nächsten Tweets dieses Nutzers gefüllt.