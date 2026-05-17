from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, field
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import HTMLResponse, Response

from .baker import BakeOptions, bake_epub_bytes
from .codex import CodexOptions, DEFAULT_MODEL, DEFAULT_REASONING_EFFORT


@dataclass
class BakeJob:
    id: str
    status: str = "queued"
    progress: int = 0
    message: str = "In coda"
    filename: str | None = None
    content: bytes | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
    error: str | None = None


app = FastAPI(title="pizza-baker", version="0.1.0")
_jobs: dict[str, BakeJob] = {}
_jobs_lock = threading.Lock()


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    return _INDEX_HTML


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/jobs")
async def create_job(
    file: UploadFile = File(...),
    model: str = Form(DEFAULT_MODEL),
    reasoning_effort: str = Form(DEFAULT_REASONING_EFFORT),
    concept_min_words: int = Form(300),
    max_preview_chars: int = Form(1600),
    use_codex: bool = Form(True),
) -> dict[str, str]:
    source_name = file.filename or "book.epub"
    if not source_name.lower().endswith(".epub"):
        raise HTTPException(status_code=400, detail="Upload an EPUB file.")
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    job = BakeJob(id=uuid.uuid4().hex)
    with _jobs_lock:
        _jobs[job.id] = job

    thread = threading.Thread(
        target=_run_job,
        args=(
            job.id,
            data,
            source_name,
            model.strip() or DEFAULT_MODEL,
            reasoning_effort.strip() or DEFAULT_REASONING_EFFORT,
            max(1, concept_min_words),
            max(100, max_preview_chars),
            use_codex,
        ),
        daemon=True,
    )
    thread.start()
    return {"job_id": job.id}


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str) -> dict[str, Any]:
    job = _require_job(job_id)
    return {
        "id": job.id,
        "status": job.status,
        "progress": job.progress,
        "message": job.message,
        "filename": job.filename,
        "metadata": job.metadata,
        "error": job.error,
        "download_url": f"/api/jobs/{job.id}/download" if job.status == "done" else None,
    }


@app.get("/api/jobs/{job_id}/download")
def download_job(job_id: str) -> Response:
    job = _require_job(job_id)
    if job.status != "done" or job.content is None or job.filename is None:
        raise HTTPException(status_code=409, detail="Job is not ready.")
    return Response(
        content=job.content,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{job.filename}"'},
    )


def _run_job(
    job_id: str,
    data: bytes,
    source_name: str,
    model: str,
    reasoning_effort: str,
    concept_min_words: int,
    max_preview_chars: int,
    use_codex: bool,
) -> None:
    def progress(percent: int, message: str) -> None:
        _update_job(job_id, progress=percent, message=message, status="running")

    try:
        progress(1, "Avvio conversione")
        result = bake_epub_bytes(
            data,
            source_name=source_name,
            options=BakeOptions(
                use_codex=use_codex,
                codex=CodexOptions(
                    model=model,
                    reasoning_effort=reasoning_effort,
                    max_preview_chars=max_preview_chars,
                    concept_min_words=concept_min_words,
                ),
                progress=progress,
            ),
        )
        _update_job(
            job_id,
            status="done",
            progress=100,
            message="Completato",
            filename=result.filename,
            content=result.document_bytes,
            metadata=result.metadata,
        )
    except Exception as exc:
        _update_job(
            job_id,
            status="error",
            progress=100,
            message="Conversione fallita",
            error=str(exc),
        )


def _require_job(job_id: str) -> BakeJob:
    with _jobs_lock:
        job = _jobs.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found.")
    return job


def _update_job(job_id: str, **changes: Any) -> None:
    with _jobs_lock:
        job = _jobs[job_id]
        for key, value in changes.items():
            setattr(job, key, value)


_INDEX_HTML = """
<!doctype html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>pizza-baker</title>
  <style>
    :root {
      color-scheme: light;
      --paper: #fff9ef;
      --ink: #211a16;
      --muted: #756a61;
      --line: #e7d7c5;
      --tomato: #c83f31;
      --basil: #2d7a52;
      --dough: #f5e4c8;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background: var(--paper);
      color: var(--ink);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    main {
      width: min(100%, 560px);
      min-height: 100vh;
      margin: 0 auto;
      padding: 20px;
      display: flex;
      flex-direction: column;
      justify-content: center;
      gap: 16px;
    }
    h1 {
      margin: 0;
      font-size: 34px;
      line-height: 1;
      letter-spacing: 0;
    }
    p { margin: 0; color: var(--muted); line-height: 1.45; }
    form, .result {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: #fffdf8;
      padding: 16px;
      display: grid;
      gap: 14px;
    }
    label {
      display: grid;
      gap: 6px;
      color: var(--muted);
      font-size: 13px;
      font-weight: 700;
    }
    input, select, button {
      width: 100%;
      min-height: 44px;
      border-radius: 8px;
      border: 1px solid var(--line);
      background: white;
      color: var(--ink);
      padding: 10px 12px;
      font: inherit;
    }
    input[type="checkbox"] {
      width: 20px;
      min-height: 20px;
      padding: 0;
    }
    .check {
      display: flex;
      align-items: center;
      gap: 10px;
      color: var(--ink);
    }
    button {
      border-color: var(--tomato);
      background: var(--tomato);
      color: white;
      font-weight: 800;
    }
    button:disabled { opacity: .58; }
    progress {
      width: 100%;
      height: 14px;
      accent-color: var(--basil);
    }
    .row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }
    a.download {
      display: inline-flex;
      min-height: 44px;
      align-items: center;
      justify-content: center;
      border-radius: 8px;
      background: var(--basil);
      color: white;
      text-decoration: none;
      font-weight: 800;
    }
    .hidden { display: none; }
    @media (max-width: 430px) {
      main { justify-content: flex-start; padding: 16px; }
      .row { grid-template-columns: 1fr; }
      h1 { font-size: 30px; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>pizza-baker</h1>
      <p>Converti EPUB in .pizzabook usando Codex per decidere range, senza riscrivere il testo.</p>
    </header>

    <form id="form">
      <label>
        EPUB
        <input id="file" name="file" type="file" accept=".epub,application/epub+zip" required>
      </label>
      <div class="row">
        <label>
          Modello
          <input name="model" value="gpt-5.5">
        </label>
        <label>
          Reasoning
          <select name="reasoning_effort">
            <option value="low">low</option>
            <option value="medium">medium</option>
            <option value="high">high</option>
          </select>
        </label>
      </div>
      <div class="row">
        <label>
          Min parole/concept
          <input name="concept_min_words" type="number" min="1" value="300">
        </label>
        <label>
          Preview chars
          <input name="max_preview_chars" type="number" min="100" value="1600">
        </label>
      </div>
      <label class="check">
        <input name="use_codex" type="checkbox" checked>
        Usa Codex
      </label>
      <button id="submit" type="submit">Cuoci .pizzabook</button>
    </form>

    <section id="result" class="result hidden">
      <progress id="progress" value="0" max="100"></progress>
      <p id="message">In attesa</p>
      <a id="download" class="download hidden" href="#">Scarica .pizzabook</a>
    </section>
  </main>
  <script>
    const form = document.getElementById('form');
    const submit = document.getElementById('submit');
    const result = document.getElementById('result');
    const progress = document.getElementById('progress');
    const message = document.getElementById('message');
    const download = document.getElementById('download');

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      submit.disabled = true;
      download.classList.add('hidden');
      result.classList.remove('hidden');
      progress.value = 0;
      message.textContent = 'Upload EPUB';

      const data = new FormData(form);
      data.set('use_codex', form.use_codex.checked ? 'true' : 'false');
      const response = await fetch('/api/jobs', { method: 'POST', body: data });
      if (!response.ok) {
        message.textContent = await response.text();
        submit.disabled = false;
        return;
      }
      const created = await response.json();
      poll(created.job_id);
    });

    async function poll(jobId) {
      const response = await fetch(`/api/jobs/${jobId}`);
      const job = await response.json();
      progress.value = job.progress || 0;
      message.textContent = `${job.progress || 0}% - ${job.message || job.status}`;
      if (job.status === 'done') {
        download.href = job.download_url;
        download.download = job.filename || 'book.pizzabook';
        download.classList.remove('hidden');
        submit.disabled = false;
        return;
      }
      if (job.status === 'error') {
        message.textContent = job.error || 'Conversione fallita';
        submit.disabled = false;
        return;
      }
      setTimeout(() => poll(jobId), 1500);
    }
  </script>
</body>
</html>
"""
