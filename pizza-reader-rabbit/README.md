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

### Deploy della creation con GitHub Pages

La root del sito GitHub Pages deve essere il contenuto di questa cartella (`pizza-reader-rabbit/`). Il repository contiene già il workflow:

```text
.github/workflows/deploy-rabbit-pages.yml
```

Per usarlo:

1. abilita **Settings → Pages → Source → GitHub Actions** nel repository GitHub;
2. fai push/merge su `main` o `master`, oppure lancia manualmente il workflow **Deploy Rabbit creation to GitHub Pages** da **Actions**;
3. usa l'URL pubblicato, di solito `https://<utente>.github.io/<repo>/`, come URL della creation Rabbit.

Dati suggeriti per il QR di installazione della creation:

```json
{
  "title": "Pizza Reader",
  "url": "https://<utente>.github.io/<repo>/",
  "description": "Reader one-word-at-a-time per libri .pizzabook.json",
  "themeColor": "#fff4df"
}
```

### Hosting dei libri

Carica `book.pizzabook.json` su hosting HTTPS pubblico con CORS compatibile con `fetch`, ad esempio:

- la stessa GitHub Pages della creation, dentro `pizza-reader-rabbit/books/`
- GitHub Pages su un altro repo
- Netlify
- Supabase public bucket
- CDN/static hosting

Se usi la stessa GitHub Pages, il libro sarà raggiungibile ad esempio qui:

```text
https://<utente>.github.io/<repo>/books/book.pizzabook.json
```

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
