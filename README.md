# Pizza Reader

Repository con:

- `pizza-reader/`: app Flutter esistente.
- `pizza-baker/`: tool Python/FastAPI per convertire EPUB in documenti PizzaReader.
- `pizza-reader-rabbit/`: Rabbit r1 creation statica HTML/CSS/JS.

## Rabbit r1 MVP

La creation Rabbit legge solo `.pizzabook.json` non compressi, generati ad esempio con:

```bash
cd pizza-baker
uv run pizza-baker bake book.epub --plain-json -o book.pizzabook.json
```

Poi il JSON va pubblicato su HTTPS con CORS ok e importato da Rabbit tramite QR.

## Deploy GitHub Pages

Questo repo include una GitHub Action che pubblica automaticamente la creation statica `pizza-reader-rabbit/` su GitHub Pages quando fai push su `main` o `master`.

Nel repository GitHub:

1. vai in **Settings → Pages**;
2. in **Build and deployment → Source** scegli **GitHub Actions**;
3. vai in **Actions** e lancia, o attendi, il workflow **Deploy Rabbit creation to GitHub Pages**.

L'URL della creation sarà mostrato nel riepilogo del deploy, tipicamente:

```text
https://<utente>.github.io/<repo>/
```

La root pubblicata rileva se non sta girando sul Rabbit: in quel caso mostra direttamente il QR di installazione/apertura della creation invece del reader.

La pagina pubblicata include anche un generatore QR completo:

```text
https://<utente>.github.io/<repo>/qr.html
```

Aprila da telefono o computer per mostrare il QR di installazione della creation e generare QR per i libri.

Per usare GitHub Pages anche per i libri, carica i `.pizzabook.json` dentro una sottocartella pubblicata, ad esempio `pizza-reader-rabbit/books/`. L'URL da trasformare in QR sarà allora:

```text
https://<utente>.github.io/<repo>/books/libro.pizzabook.json
```

Vedi `pizza-reader-rabbit/README.md`.
