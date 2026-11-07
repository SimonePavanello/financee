# Financiee

App Flutter per la gestione delle finanze personali: entrate, spese, categorie,
dashboard con grafici e report CSV. Piattaforme attuali: **Android** e **web**
(iOS in arrivo: il codice non ha nulla di specifico per Android).

## Funzioni

- **Conti**: più conti con titolo, icona, colore e saldo iniziale (anche
  negativo, es. carta di credito); saldo attuale e patrimonio totale. Ogni
  spesa o entrata appartiene a un conto, che il form chiede sempre (con un
  solo conto viene usato quello). Eliminando un conto lo si unisce a un altro:
  movimenti e saldo non vanno persi.
- **Trasferimenti tra conti**: es. 100 € da "Risparmi" a "Conto principale"
  con descrizione e data. Non contano né come entrate né come spese, ma
  aggiornano i saldi dei due conti.
- **Buoni pasto** (Impostazioni → Buoni pasto): imposti quanto vale un buono
  (es. 8 €) e attivi il conto "Buoni pasto", su cui carichi i buoni ricevuti
  ("Aggiungi buoni ricevuti", anche dalla scheda Conti) come entrata della
  categoria Buoni pasto. In una spesa puoi pagare una parte con i buoni:
  scegli quanti buoni usi (− / +, oppure "Usa il massimo") e il form mostra
  quanto esce da ciascun conto. Es. spesa di 180 € con 17 buoni da 8 €:
  136 € dal conto Buoni pasto e 44 € dal conto scelto. Nei report la spesa
  conta per intero nella sua categoria e ogni conto solo per la sua parte; il
  saldo del conto dei buoni si vede anche come numero di buoni. In dashboard
  la card "Buoni pasto" riassume il mese per categoria ("Spesa: hai speso
  300,00 € di cui 140,00 € in buoni pasto"); toccando una riga si apre la
  percentuale coperta dai buoni (46,7%) con la barra e i due importi.
- **Debiti** (scheda Conti → Debiti): crei un debito con nome, importo da
  restituire, icona e colore (es. "Prestito auto" 5.000 €). Nel form di una
  spesa scegli "Pagamento di un debito" e il form dice quanto resterà dopo
  quel pagamento. Ogni debito mostra quanto resta, la percentuale restituita
  e una barra che si riempie fino a "Estinto"; toccandolo si apre il
  dettaglio con l'andamento del residuo nel tempo e tutti i pagamenti
  collegati (da cui puoi anche registrarne uno nuovo). In dashboard compaiono
  i debiti ancora da estinguere. Eliminando un debito i pagamenti restano tra
  i movimenti. Gli importi dei debiti seguono la modalità privacy.
- **Movimenti**: inserimento rapido di entrate, spese e trasferimenti (importo,
  conto, categoria, data, descrizione), lista raggruppata per giorno con
  totale giornaliero, ricerca, filtri Entrate/Uscite/Trasferimenti e per conto
  con i totali del risultato, modifica e cancellazione con swipe e "Annulla".
- **Categorie**: 19 categorie predefinite in italiano, creazione e modifica con
  nome, colore (18) e icona (51). Se elimini una categoria che ha movimenti,
  l'app ti chiede in quale categoria spostarli: nessun dato va perso.
- **Dashboard** (per mese): saldo con gradiente animato, entrate/uscite, tasso di
  risparmio, variazione delle spese rispetto al mese precedente, media
  giornaliera, spesa più alta, categoria top, ciambella interattiva per
  categoria, barre entrate/uscite degli ultimi 6 mesi, ultimi movimenti.
- **Report** per mese, anno o intervallo libero: indicatori, ripartizione per
  categoria con numero di movimenti e importo medio, andamento e tabella mese
  per mese.
- **Export CSV**, pensato per Excel/Numbers/Google Sheets in italiano:
  - *Report completo*: riepilogo con spiegazioni in chiaro, saldi dei conti a
    inizio e fine periodo (entrate, uscite, trasferimenti netti, variazione),
    uscite ed entrate per categoria (totale, %, n. movimenti, media), andamento
    mensile con saldo cumulato, elenco dei trasferimenti, dettaglio cronologico
    con conto, colonne Entrata/Uscita separate e saldo progressivo.
  - *Solo movimenti*: una riga per movimento con conto e importo con segno, per
    filtri e tabelle pivot; ogni trasferimento diventa due righe (uscita dal
    conto di origine, entrata in quello di destinazione), e così una spesa
    pagata in parte con i buoni pasto (una riga per conto con la sua parte).
  - Separatore `;`, decimali con la virgola, date `gg/mm/aaaa`, UTF-8 con BOM
    (accenti ed € corretti in Excel), protezione dalle formule nei testi.
  - Sul web il file si scarica; su Android si apre il menu di condivisione
    (Drive, email, WhatsApp, "Salva in File"...).
  - Esempi in [docs/esempi](docs/esempi).
- **Import da Sossoldi** (Impostazioni → Importa da Sossoldi): legge l'export
  CSV di Sossoldi, mostra un'anteprima di come conti e categorie vengono
  trasformati (le categorie inglesi o duplicate confluiscono in quelle di
  Financiee, le altre vengono create), importa tutto in un'unica operazione e
  verifica che i saldi finali coincidano con quelli di Sossoldi. La mappatura
  è in `lib/data/import/sossoldi_import.dart`. Per provarlo senza toccare
  nulla: `dart run tool/verify_sossoldi_import.dart <export.csv>`.
- **Privacy**: saldo del mese, patrimonio e saldi dei conti compaiono come
  `•••• €` all'apertura (disattivabile in Impostazioni → Privacy). L'icona a
  occhio, o un tocco su un importo nascosto, li mostra; un altro tocco
  sull'occhio li ricopre. Movimenti e statistiche restano visibili.
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

Schema del database (versione 4): `accounts` (con il tipo: normale o buoni
pasto), `categories`, `debts` (debiti con l'importo da restituire),
`transactions` (entrate/uscite, ciascuna con conto e categoria; una spesa può
avere una parte `voucher_cents` pagata dal conto dei buoni
`voucher_account_id` ed essere il pagamento di un debito `debt_id`),
`transfers` (da conto → a conto). L'aggiornamento dalle versioni precedenti è
automatico (coperto da test di migrazione): dalla 1 i movimenti già
registrati finiscono in "Conto principale"; dalla 2 e dalla 3 conti e
movimenti restano com'erano, senza buoni né debiti.

## Struttura

```
lib/
  main.dart, app.dart, providers.dart   avvio, MaterialApp, provider Riverpod
  core/theme/                           colori e tema
  core/utils/                           formattazione italiana, periodi, icone/colori categorie
  data/                                 database Drift, categorie predefinite, dati di esempio
  domain/analytics.dart                 calcoli: riepiloghi, categorie, andamento mensile
  features/
    dashboard/  transactions/  accounts/  categories/  reports/  settings/  shell/
  widgets/                              componenti condivisi (card, grafici, righe movimento)
web/sqlite3.wasm, web/drift_worker.js   database sul web
tool/                                   sorgente del worker Drift, generatore CSV di esempio
test/                                   test di logica, CSV e database
```

## Avvio

- **Uso quotidiano sul PC**: doppio clic su `avvia.bat`. Apre l'app su
  `http://localhost:8080` (la prima volta la compila, 1-2 minuti).
  `avvia.bat build` la ricompila dopo modifiche al codice. I dati restano nel
  browser per quell'indirizzo; da Edge puoi anche installarla come app
  (menu ⋯ → App → Installa questo sito come app).
- **Sviluppo con hot reload**: `flutter run -d edge --web-port 8081`, poi `r`
  (hot reload), `R` (riavvio), `q` (esci). Usa sempre `localhost`, non
  `127.0.0.1`. Edge viene aperto con un profilo temporaneo, quindi i dati
  possono ripartire da zero a ogni sessione: usa "Dati di esempio".

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
