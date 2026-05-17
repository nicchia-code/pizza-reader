# Pizza Reader Rabbit

Creation statica per Rabbit r1: importa un libro `.pizzabook.json` via QR/URL e lo legge una parola alla volta.

## Formato libro

La creation accetta JSON non compresso:

```json
{
  "format": "pizza_reader_document",
  "version": 1,
  "content_hash": "sha256:...",
  "book": {
    "id": "pinocchio",
    "title": "Pinocchio",
    "author": "Carlo Collodi",
    "language": "it",
    "chapters": [
      { "id": "chapter-1", "title": "Capitolo 1", "text": "C'era una volta..." }
    ]
  }
}
```

`content_hash` può essere presente ma non viene validato nell'MVP. Viene validata solo la struttura minima.

## Generare un libro con pizza-baker

Dalla root del repository:

```bash
cd pizza-baker
uv run pizza-baker bake book.epub --plain-json -o book.pizzabook.json
```

Nota: l'output `.pizzabook` gzip è per PizzaReader Flutter. Per Rabbit usare `--plain-json`.

## Hosting e QR

Carica `book.pizzabook.json` su hosting HTTPS pubblico con CORS compatibile con `fetch`, ad esempio:

- GitHub Pages
- Netlify
- Supabase public bucket
- CDN/static hosting

Poi crea un QR contenente l'URL HTTPS del JSON.

Sono accettati solo:

- `https://...`
- `http://localhost...` per sviluppo

## Limiti dimensione

- fino a 2 MB: import normale
- da 2 a 5 MB: warning e conferma
- oltre 5 MB: import bloccato

## Controlli Rabbit r1

Hardware-first, touch minimo:

| Controllo | Azione |
|---|---|
| side click | play/pausa |
| side click a fine capitolo | capitolo successivo |
| long press start | hold start |
| long press end | hold stop |
| rotella giù / `scrollDown` | parola successiva |
| rotella su / `scrollUp` | parola precedente |

Touch fallback:

- Importa/scansiona QR
- conferme
- URL manuale
- WPM ±
- play/prev/next se serve durante test browser

## Scanner QR

MVP:

- usa `BarcodeDetector` se disponibile
- se non disponibile, usare il campo URL manuale

`jsQR` non è vendorizzato in questa versione.

## Sviluppo locale

Servire la cartella con un server statico, per esempio:

```bash
cd pizza-reader-rabbit
python3 -m http.server 8080
```

Apri `http://localhost:8080`.

Fallback tastiera browser:

- spazio/enter: play/pausa
- frecce destra/giù: parola successiva
- frecce sinistra/su: parola precedente
- `+` / `-`: WPM
