// Sorgente del web worker usato da Drift sul web.
// Ricompilare dopo un aggiornamento di drift con:
//   dart compile js -O4 tool/drift_worker.dart -o web/drift_worker.js
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
