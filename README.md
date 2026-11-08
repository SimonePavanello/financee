# Financee

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
- **Debiti** (scheda Conti → Debiti), in due modalità:
  - *Importo totale*, per gli acquisti divisi in poche rate (PayPal in 3
    rate, Klarna) o per soldi da restituire a qualcuno: nome e importo da
    restituire (es. "Klarna divano" 600 €).
  - *A rate*, per prestiti e finanziamenti: importo della rata, numero di
    rate e rate già pagate prima di registrarle qui (es. "Prestito auto",
    60 rate da 250 € di cui 12 già pagate: restano 12.000 € in 48 rate).
    Gli interessi non si calcolano: il totale è rata × numero di rate.

  Nel form di una spesa scegli "Pagamento di un debito" e il form dice quanto
  resterà dopo quel pagamento (per un debito a rate propone la rata come
  importo e dice a che rata sei, es. "15 rate su 60 pagate"). Le rate si
  contano dall'importo restituito: due rate pagate insieme contano due, e
  un'estinzione anticipata chiude il debito. Ogni debito mostra quanto resta,
  la percentuale restituita
  e una barra che si riempie fino a "Estinto"; toccandolo si apre il
  dettaglio con l'andamento del residuo nel tempo e tutti i pagamenti
  collegati (da cui puoi anche registrarne uno nuovo). In dashboard compaiono
  i debiti ancora da estinguere. Eliminando un debito i pagamenti restano tra
  i movimenti. Gli importi dei debiti seguono la modalità privacy.
- **Obiettivi di risparmio** (scheda Conti → Obiettivi di risparmio): dai a
  un conto un traguardo per il suo saldo, con nome e scadenza facoltativa
  (es. "Fondo emergenza", 5.000 € su "Risparmi" entro il 31/12/2027). Quanto
  hai messo da parte è il saldo del conto: l'obiettivo mostra percentuale,
  barra e quanto manca, quanto serve al mese per arrivare alla scadenza e il
  ritmo degli ultimi 3 mesi, con lo stato ("Sei in linea", "In ritardo",
  "Saldo fermo", "Raggiunto") e la data in cui ci arrivi a quel ritmo. Il
  dettaglio ha il grafico del saldo nell'ultimo anno con la linea
  dell'obiettivo e "Aggiungi soldi" (un trasferimento verso quel conto).
  Ogni conto ha al massimo un obiettivo; gli obiettivi compaiono anche in
  dashboard e sulla card del conto. Unendo due conti l'obiettivo passa al
  conto rimasto, se non ne ha già uno.
- **Backup e ripristino** (Impostazioni → Backup): "Esporta backup" salva un
  file `financee-backup-AAAA-MM-GG.json` con tutti i dati (conti, categorie,
  movimenti, trasferimenti, debiti, obiettivi e valore del buono pasto); sul
  web si scarica, su Android si condivide (Drive, email, "Salva in File").
  "Ripristina da un backup" mostra prima cosa contiene il file (conti,
  movimenti, periodo) e lo confronta con i dati attuali, poi sostituisce
  tutto in un'unica transazione: se il file è danneggiato o ha riferimenti
  non validi non cambia nulla. Prima del ripristino scarica, se vuoi, un
  backup dei dati attuali. Se il backup manca o ha più di 30 giorni, la
  dashboard lo ricorda (rimandabile di una settimana). I backup di versioni
  precedenti si ripristinano anche nelle versioni successive dell'app.
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
  Financee, le altre vengono create), importa tutto in un'unica operazione e
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

Schema del database (versione 6): `accounts` (con il tipo: normale o buoni
pasto), `categories`, `debts` (debiti a importo totale o a rate: rata,
numero di rate e rate già pagate; `amount_cents` è sempre il totale),
`transactions` (entrate/uscite, ciascuna con conto e categoria; una spesa può
avere una parte `voucher_cents` pagata dal conto dei buoni
`voucher_account_id` ed essere il pagamento di un debito `debt_id`),
`transfers` (da conto → a conto), `savings_goals` (obiettivo di un conto:
saldo da raggiungere e scadenza facoltativa). L'aggiornamento dalle versioni
precedenti è automatico (coperto da test di migrazione): dalla 1 i movimenti
già registrati finiscono in "Conto principale"; dalla 2, 3, 4 e 5 conti e
movimenti restano com'erano, senza buoni, debiti o obiettivi.

Il database si chiama `financee` (file `financee.sqlite` su Android/iOS,
database `financee` nel browser). Fino all'8/11/2026 l'app si chiamava
Financiee e il database `financiee`: al primo avvio `prepareAppDatabase`
(`lib/data/connection.dart`) ne copia tutti i dati nel nuovo, controlla che
la copia sia identica tabella per tabella e solo allora elimina il vecchio;
se qualcosa va storto continua a usare il vecchio e riprova all'avvio dopo.

Il file di backup è JSON: per ogni tabella i nomi delle colonne e le righe
così come sono nel database (date in secondi dal 1970), più la versione dello
schema da cui è stato creato. Formato e ripristino sono in
`lib/data/backup/backup.dart`; si ripristinano anche i backup creati quando
l'app si chiamava Financiee.

## Icona

Il monogramma F (indaco-viola, con la barra centrale e la moneta verde menta)
è disegnato in `tool/generate_app_icon.dart` e, uguale, nel logo dell'app
(`lib/widgets/app_logo.dart`). Per rigenerare le immagini:

```bash
dart run tool/generate_app_icon.dart     # assets/branding/ e icone web
dart run flutter_launcher_icons          # icone Android (e iOS sul Mac)
```

Android usa l'icona adattiva (sfondo sfumato e monogramma in primo piano) e,
da Android 13, quella monocromatica per le icone a tema.

## Struttura

```
lib/
  main.dart, app.dart, providers.dart   avvio, MaterialApp, provider Riverpod
  core/theme/                           colori e tema
  core/utils/                           formattazione italiana, periodi, icone/colori categorie
  data/                                 database Drift, categorie predefinite, dati di esempio
  data/backup/                          formato del backup, esportazione e ripristino
  domain/                               calcoli: riepiloghi, debiti, obiettivi, buoni pasto
  features/
    dashboard/  transactions/  accounts/  categories/  reports/  settings/  shell/
    backup/  debts/  goals/  meal_vouchers/
  widgets/                              componenti condivisi (card, grafici, logo, righe movimento)
assets/branding/                        immagini sorgente dell'icona
web/sqlite3.wasm, web/drift_worker.js   database sul web
tool/                                   worker Drift, generatore CSV di esempio e dell'icona
test/                                   test di logica, CSV, database e backup
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
dart test                                                  # test (logica, CSV, database, backup)
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

## iOS (sul Mac)

La cartella `ios/` non c'è ancora: si crea sul Mac, con Xcode installato.

```bash
flutter create --platforms=ios --org com.financee .
```

Poi in `pubspec.yaml` si mette `ios: true` sotto `flutter_launcher_icons` e
si lancia `dart run flutter_launcher_icons` per le icone. L'identificativo
iOS sarà `com.financee.financee`; per averlo uguale ad Android
(`com.financee.app`) si cambia in Xcode (Runner → Signing & Capabilities).

## Prossimi passi possibili

Movimenti ricorrenti, budget mensili per categoria con avvisi, crediti
(soldi prestati), import CSV/estratti conto, sottocategorie,
sincronizzazione tra dispositivi, blocco con PIN/biometria, iOS.
