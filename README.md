# Financiee

App Flutter per la gestione delle finanze personali: entrate, spese, categorie,
dashboard con grafici e report CSV. Piattaforme attuali: **Android** e **web**
(iOS in arrivo: il codice non ha nulla di specifico per Android).

## Funzioni

- **Movimenti**: inserimento rapido di entrate e spese (importo, categoria, data,
  descrizione), lista raggruppata per giorno con totale giornaliero, ricerca,
  filtri Entrate/Uscite con i totali del risultato, modifica e cancellazione
  con swipe e "Annulla".
- **Categorie**: 19 categorie predefinite in italiano, creazione e modifica con
  nome, colore (18) e icona (50). Se elimini una categoria che ha movimenti,
  l'app ti chiede in quale categoria spostarli: nessun dato va perso.
- **Dashboard** (per mese): saldo con gradiente animato, entrate/uscite, tasso di
  risparmio, variazione delle spese rispetto al mese precedente, media
  giornaliera, spesa più alta, categoria top, ciambella interattiva per
  categoria, barre entrate/uscite degli ultimi 6 mesi, ultimi movimenti.
- **Report** per mese, anno o intervallo libero: indicatori, ripartizione per
  categoria con numero di movimenti e importo medio, andamento e tabella mese
  per mese.
- **Export CSV**, pensato per Excel/Numbers/Google Sheets in italiano:
  - *Report completo*: riepilogo con spiegazioni in chiaro, uscite ed entrate
    per categoria (totale, %, n. movimenti, media), andamento mensile con saldo
    cumulato, dettaglio cronologico con colonne Entrata/Uscita separate e saldo
    progressivo, riga di totale.
  - *Solo movimenti*: una riga per movimento con importo con segno, per filtri
    e tabelle pivot.
  - Separatore `;`, decimali con la virgola, date `gg/mm/aaaa`, UTF-8 con BOM
    (accenti ed € corretti in Excel), protezione dalle formule nei testi.
  - Sul web il file si scarica; su Android si apre il menu di condivisione
    (Drive, email, WhatsApp, "Salva in File"...).
  - Esempi in [docs/esempi](docs/esempi).
- Tema chiaro, scuro o di sistema; layout adattivo (barra in basso su telefono,
  barra laterale su tablet e desktop); dati di esempio per provare l'app.

## Stack

| Ambito | Scelta |
|---|---|
| UI | Flutter 3.47 · Material 3 · font Plus Jakarta Sans incluso negli asset |
| Stato | Riverpod 3 |
| Database | Drift (SQLite): file nativo su Android, SQLite WebAssembly + IndexedDB/OPFS sul web |
| Grafici | fl_chart |
| Export | share_plus (mobile), download via `package:web` (web) |

Gli importi sono salvati in **centesimi interi** (niente errori di arrotondamento).

## Struttura

```
lib/
  main.dart, app.dart, providers.dart   avvio, MaterialApp, provider Riverpod
  core/theme/                           colori e tema
  core/utils/                           formattazione italiana, periodi, icone/colori categorie
  data/                                 database Drift, categorie predefinite, dati di esempio
  domain/analytics.dart                 calcoli: riepiloghi, categorie, andamento mensile
  features/
    dashboard/  transactions/  categories/  reports/  settings/  shell/
  widgets/                              componenti condivisi (card, grafici, righe movimento)
web/sqlite3.wasm, web/drift_worker.js   database sul web
tool/                                   sorgente del worker Drift, generatore CSV di esempio
test/                                   test di logica, CSV e database
```

## Comandi

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # dopo modifiche alle tabelle
dart test                                                  # test (logica, CSV, database)
flutter build web --no-tree-shake-icons                    # build web in build/web
flutter run -d edge                                        # web in sviluppo
flutter run                                                # Android (serve Android Studio/SDK)
dart run tool/generate_sample_report.dart                  # rigenera docs/esempi
```

Dopo un aggiornamento di `drift` va ricompilato il worker web:
`dart compile js -O4 tool/drift_worker.dart -o web/drift_worker.js`; dopo un
aggiornamento di `sqlite3` va scaricato il `sqlite3.wasm` della stessa versione
dalle release di [sqlite3.dart](https://github.com/simolus3/sqlite3.dart/releases).

## Note su questo PC (Windows)

- Flutter è installato in `D:\Tools\flutter` (aggiunto al PATH utente).
- **Smart App Control** di Windows è attivo e blocca gli eseguibili non firmati
  del motore Flutter (`flutter_tester.exe`, `impellerc.exe`, `gen_snapshot.exe`,
  `font-subset.exe`). Conseguenze:
  - `flutter test` non parte → i test sono scritti in Dart puro e si lanciano
    con `dart test`;
  - la build web funziona con `--no-tree-shake-icons`;
  - le build/esecuzioni Android (`flutter run`, `flutter build apk`)
    verranno bloccate finché Smart App Control resta attivo. In alternativa si
    può sviluppare in WSL2, in un container o su un'altra macchina.
- Per Android serve installare Android Studio (SDK + emulatore) e poi
  `flutter doctor --android-licenses`.

## Prossimi passi possibili

Conti multipli (contanti, carta, banca) e trasferimenti, movimenti ricorrenti,
budget mensili per categoria con avvisi, import CSV/estratti conto,
sottocategorie, backup/sincronizzazione, blocco con PIN/biometria, iOS.
