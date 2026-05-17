# Pizza Reader Rabbit

Creation statica per Rabbit r1: importa un libro `.pizzabook.json` via QR e lo legge una parola alla volta.

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
3. apri l'URL pubblicato, di solito `https://<utente>.github.io/<repo>/`, da desktop/telefono: verrai portato direttamente al generatore QR.

Il generatore QR è qui:

```text
https://<utente>.github.io/<repo>/qr.html
```

Apri `qr.html` da telefono o computer per mostrare:

- il QR di installazione/apertura della creation;
- un QR libro che apre Pizza Reader sul Rabbit e importa automaticamente l'URL `.pizzabook.json`.

Dati contenuti nel QR di installazione della creation:

```json
{
  "title": "Pizza Reader",
  "url": "https://<utente>.github.io/<repo>/?app=1",
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

Poi apri `qr.html`, incolla questo URL e genera il QR libro. Il QR libro non avvia la camera dentro la creation: apre Pizza Reader con `?book=<url>` e importa automaticamente il JSON.

Sono accettati solo:

- `https://...`
- `http://localhost...` per sviluppo

## Limiti dimensione

- fino a 5 MB: import consentito
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

- WPM ±
- play/prev/next se serve durante test browser

## Import via QR

La creation non avvia più direttamente la camera: su Rabbit questa strada può essere instabile. Il QR libro generato da `qr.html` apre invece la creation con un parametro `book`, e la app scarica/importa automaticamente quel file.

## Sviluppo locale

Servire la cartella con un server statico, per esempio:

```bash
cd pizza-reader-rabbit
python3 -m http.server 8080
```

Apri `http://localhost:8080`: in un browser normale la root reindirizza a `qr.html`, anche se l'URL contiene `?app=1`. Per forzare davvero il reader durante lo sviluppo usa:

```text
http://localhost:8080/?forceReader=1
```

Fallback tastiera browser:

- spazio/enter: play/pausa
- frecce destra/giù: parola successiva
- frecce sinistra/su: parola precedente
- `+` / `-`: WPM
