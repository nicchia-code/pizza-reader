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

Poi il JSON va pubblicato su HTTPS con CORS ok e importato da Rabbit tramite QR o URL manuale.

Vedi `pizza-reader-rabbit/README.md`.
