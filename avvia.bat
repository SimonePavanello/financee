@echo off
rem Avvia Financiee nel browser (versione web compilata).
rem   avvia.bat          usa la build esistente (la crea se manca)
rem   avvia.bat build    ricompila prima di avviare (dopo modifiche al codice)
rem I dati restano salvati nel browser per l'indirizzo http://localhost:PORT
rem Variabili opzionali: PORT (predefinita 8080), NO_BROWSER=1 per non aprire il browser.

setlocal
cd /d "%~dp0"
if not defined PORT set PORT=8080
set "PATH=%PATH%;D:\Tools\flutter\bin"

if /i "%~1"=="build" goto build
if exist "build\web\index.html" goto serve

:build
echo Compilo la versione web (circa 1-2 minuti)...
call flutter build web --no-tree-shake-icons --no-wasm-dry-run
if errorlevel 1 (
  echo Compilazione non riuscita.
  pause
  exit /b 1
)

:serve
echo.
echo Financiee e' disponibile su http://localhost:%PORT%
echo Chiudi questa finestra (o premi Ctrl+C) per fermarla.
echo.
if not defined NO_BROWSER start "" "http://localhost:%PORT%"
python -m http.server %PORT% --bind 127.0.0.1 --directory build\web
