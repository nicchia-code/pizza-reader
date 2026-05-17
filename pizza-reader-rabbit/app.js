/* global PizzaQrScanner, closeWebView */
(() => {
  const STORAGE_KEY = "pizza-reader-rabbit-state-v1";
  const SOFT_LIMIT = 2 * 1024 * 1024;
  const HARD_LIMIT = 5 * 1024 * 1024;
  const DEFAULT_WPM = 220;
  const MIN_WPM = 100;
  const MAX_WPM = 600;
  const WPM_STEP = 20;

  const state = {
    bookUrl: "",
    document: null,
    book: null,
    chapterIndex: 0,
    wordIndex: 0,
    wpm: DEFAULT_WPM,
    playing: false,
    holdMode: false,
    chapterEnded: false,
    words: [],
    timer: null,
    saveTimer: null,
  };

  const el = {
    subtitle: id("subtitle"),
    importButton: id("importButton"),
    emptyImportButton: id("emptyImportButton"),
    closeButton: id("closeButton"),
    readerView: id("readerView"),
    emptyView: id("emptyView"),
    importView: id("importView"),
    chapterLabel: id("chapterLabel"),
    wordBefore: id("wordBefore"),
    pivot: id("pivot"),
    wordAfter: id("wordAfter"),
    wordStage: id("wordStage"),
    progressBar: id("progressBar"),
    statusText: id("statusText"),
    wpmText: id("wpmText"),
    chapterEnd: id("chapterEnd"),
    nextChapterButton: id("nextChapterButton"),
    wpmDown: id("wpmDown"),
    wpmUp: id("wpmUp"),
    prevWord: id("prevWord"),
    nextWord: id("nextWord"),
    playPause: id("playPause"),
    scanInfo: id("scanInfo"),
    scanButton: id("scanButton"),
    stopScanButton: id("stopScanButton"),
    cameraPreview: id("cameraPreview"),
    urlForm: id("urlForm"),
    bookUrl: id("bookUrl"),
    cancelImportButton: id("cancelImportButton"),
  };

  let scanner = null;

  boot();

  async function boot() {
    if (!await shouldRunReader()) {
      renderInstallLanding();
      return;
    }
    init();
  }

  async function shouldRunReader() {
    if (isForcedReaderMode()) return true;
    for (let attempt = 0; attempt < 8; attempt += 1) {
      if (isRabbitRuntime()) return true;
      await delay(100);
    }
    return false;
  }

  function isForcedReaderMode() {
    const params = new URLSearchParams(window.location.search);
    return params.has("app") || params.has("rabbit") || params.has("forceReader");
  }

  function isRabbitRuntime() {
    const ua = (navigator.userAgent || "").toLowerCase();
    return ua.includes("rabbit")
      || ua.includes("rabbitos")
      || typeof window.PluginMessageHandler !== "undefined"
      || typeof window.closeWebView !== "undefined"
      || typeof window.creationStorage !== "undefined"
      || typeof window.creationSensors !== "undefined";
  }

  function renderInstallLanding() {
    stopScan();
    stopPlayback();
    const app = document.querySelector(".app");
    if (!app) return;

    const creationUrl = new URL("./", window.location.href).href;
    const installPayload = {
      title: "Pizza Reader",
      url: creationUrl,
      description: "Reader one-word-at-a-time per libri .pizzabook.json",
      themeColor: "#fff4df",
    };
    const qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=8&data="
      + encodeURIComponent(JSON.stringify(installPayload));

    app.className = "browser-install";
    app.innerHTML = `
      <section class="install-card">
        <p class="install-eyebrow">Pizza Reader Rabbit</p>
        <h1>Aprilo sul Rabbit r1</h1>
        <p>Questa pagina non sembra essere in esecuzione su un Rabbit. Scansiona questo QR con il Rabbit per installare/aprire la creation.</p>
        <div class="install-qr-wrap">
          <img src="${escapeAttribute(qrUrl)}" alt="QR per installare Pizza Reader sul Rabbit r1">
        </div>
        <label class="install-label" for="installUrl">URL creation</label>
        <input id="installUrl" class="install-url" value="${escapeAttribute(creationUrl)}" readonly>
        <div class="install-actions">
          <a href="qr.html">Pagina QR completa</a>
          <a href="?app=1">Forza apertura app</a>
        </div>
      </section>
    `;
  }

  function delay(ms) {
    return new Promise((resolve) => window.setTimeout(resolve, ms));
  }

  function escapeAttribute(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  async function init() {
    bindUi();
    bindRabbitHardware();
    bindKeyboardFallback();
    if (typeof closeWebView !== "undefined" && closeWebView && closeWebView.postMessage) {
      el.closeButton.classList.remove("hidden");
    }
    await loadState();
    hydrateWords();
    render();
  }

  function bindUi() {
    el.importButton.addEventListener("click", showImport);
    el.emptyImportButton.addEventListener("click", showImport);
    el.cancelImportButton.addEventListener("click", hideImport);
    el.closeButton.addEventListener("click", () => closeWebView.postMessage(""));
    el.wordStage.addEventListener("click", onSideClick);
    el.playPause.addEventListener("click", onSideClick);
    el.prevWord.addEventListener("click", previousWord);
    el.nextWord.addEventListener("click", nextWord);
    el.wpmDown.addEventListener("click", () => changeWpm(-WPM_STEP));
    el.wpmUp.addEventListener("click", () => changeWpm(WPM_STEP));
    el.nextChapterButton.addEventListener("click", nextChapter);
    el.scanButton.addEventListener("click", startScan);
    el.stopScanButton.addEventListener("click", stopScan);
    el.urlForm.addEventListener("submit", (event) => {
      event.preventDefault();
      importFromUrl(el.bookUrl.value.trim());
    });
  }

  function bindRabbitHardware() {
    addHardwareListener("sideClick", onSideClick);
    addHardwareListener("longPressStart", () => startHold());
    addHardwareListener("longPressEnd", () => stopHold());
    addHardwareListener("scrollDown", () => nextWord());
    addHardwareListener("scrollUp", () => previousWord());
  }

  function bindKeyboardFallback() {
    window.addEventListener("keydown", (event) => {
      if (isTyping()) return;
      if (event.key === " " || event.key === "Enter") { event.preventDefault(); onSideClick(); }
      if (event.key === "ArrowRight" || event.key === "ArrowDown") nextWord();
      if (event.key === "ArrowLeft" || event.key === "ArrowUp") previousWord();
      if (event.key === "+" || event.key === "=") changeWpm(WPM_STEP);
      if (event.key === "-" || event.key === "_") changeWpm(-WPM_STEP);
    });
  }

  function addHardwareListener(name, handler) {
    window.addEventListener(name, handler);
    document.addEventListener(name, handler);
  }

  function onSideClick() {
    if (state.chapterEnded) {
      nextChapter();
      return;
    }
    togglePlay();
  }

  function showImport() {
    stopPlayback();
    el.importView.classList.remove("hidden");
    el.emptyView.classList.add("hidden");
    el.readerView.classList.add("hidden");
    el.scanInfo.textContent = "Inquadra un QR con URL HTTPS del libro.";
  }

  function hideImport() {
    stopScan();
    el.importView.classList.add("hidden");
    render();
  }

  async function startScan() {
    try {
      stopScan();
      scanner = new PizzaQrScanner(el.cameraPreview, (code) => {
        stopScan();
        importFromUrl(code.trim());
      }, setImportStatus);
      el.stopScanButton.classList.remove("hidden");
      await scanner.start();
    } catch (error) {
      setImportStatus(error.message || "Scanner non disponibile. Usa l'URL manuale.");
      stopScan();
    }
  }

  function stopScan() {
    if (scanner) scanner.stop();
    scanner = null;
    el.stopScanButton.classList.add("hidden");
  }

  async function importFromUrl(rawUrl) {
    try {
      const url = validateUrl(rawUrl);
      if (state.book && !window.confirm("Sostituire il libro corrente?")) return;
      setImportStatus("Controllo dimensione…");
      const response = await fetch(url, { method: "GET", mode: "cors" });
      if (!response.ok) throw new Error(`URL non raggiungibile (${response.status}).`);

      const length = Number(response.headers.get("content-length") || 0);
      if (length > HARD_LIMIT) throw new Error("Libro troppo grande: massimo 5 MB.");
      if (length > SOFT_LIMIT && !window.confirm("Libro grande: potrebbe essere lento. Continuare?")) return;

      setImportStatus("Scarico libro…");
      const text = await response.text();
      const size = new Blob([text]).size;
      if (size > HARD_LIMIT) throw new Error("Libro troppo grande: massimo 5 MB.");
      if (size > SOFT_LIMIT && length === 0 && !window.confirm("Libro grande: potrebbe essere lento. Continuare?")) return;

      let doc;
      try { doc = JSON.parse(text); } catch (_) { throw new Error("JSON non valido."); }
      const normalized = normalizeDocument(doc);
      state.bookUrl = url;
      state.document = normalized.document;
      state.book = normalized.book;
      state.chapterIndex = 0;
      state.wordIndex = 0;
      state.chapterEnded = false;
      state.playing = false;
      state.holdMode = false;
      state.wpm = state.wpm || DEFAULT_WPM;
      hydrateWords();
      await saveStateNow();
      setImportStatus(`Importato: ${state.book.title}`);
      hideImport();
    } catch (error) {
      setImportStatus(error.message || "Import fallito.");
    }
  }

  function validateUrl(rawUrl) {
    let parsed;
    try { parsed = new URL(rawUrl); } catch (_) { throw new Error("URL non valido."); }
    const isLocalhost = parsed.protocol === "http:" && ["localhost", "127.0.0.1", "::1"].includes(parsed.hostname);
    if (parsed.protocol !== "https:" && !isLocalhost) throw new Error("URL non sicuro: usa HTTPS.");
    return parsed.toString();
  }

  function normalizeDocument(doc) {
    const book = doc && doc.format === "pizza_reader_document" ? doc.book : doc;
    if (!book || typeof book !== "object") throw new Error("Documento PizzaBook non valido.");
    if (!stringValue(book.title)) throw new Error("Titolo libro mancante.");
    if (!Array.isArray(book.chapters) || book.chapters.length === 0) throw new Error("Capitoli mancanti.");
    const chapters = book.chapters.map((chapter, index) => {
      if (!chapter || !stringValue(chapter.text)) throw new Error(`Testo capitolo ${index + 1} mancante.`);
      return {
        id: stringValue(chapter.id) || `chapter-${index + 1}`,
        title: stringValue(chapter.title) || `Capitolo ${index + 1}`,
        text: String(chapter.text).trim(),
      };
    });
    return {
      document: doc && doc.format === "pizza_reader_document" ? doc : { book: { ...book, chapters } },
      book: { ...book, title: String(book.title).trim(), chapters },
    };
  }

  function hydrateWords() {
    state.words = [];
    state.chapterEnded = false;
    if (!state.book) return;
    const chapter = currentChapter();
    state.words = tokenize(chapter ? chapter.text : "");
    if (state.wordIndex >= state.words.length) {
      state.wordIndex = Math.max(0, state.words.length - 1);
      state.chapterEnded = state.words.length > 0;
    }
  }

  function tokenize(text) {
    return (text.match(/\S+/g) || []).map((raw) => ({ raw }));
  }

  function togglePlay() {
    if (!state.book || state.chapterEnded) return;
    state.playing ? stopPlayback() : startPlayback(false);
  }

  function startHold() {
    if (!state.book || state.chapterEnded) return;
    state.holdMode = true;
    startPlayback(true);
  }

  function stopHold() {
    state.holdMode = false;
    stopPlayback();
  }

  function startPlayback(hold) {
    if (!state.book || state.words.length === 0) return;
    state.playing = true;
    if (hold) state.holdMode = true;
    scheduleNext();
    render();
  }

  function stopPlayback() {
    state.playing = false;
    state.holdMode = false;
    if (state.timer) window.clearTimeout(state.timer);
    state.timer = null;
    render();
    saveSoon();
  }

  function scheduleNext() {
    if (state.timer) window.clearTimeout(state.timer);
    if (!state.playing) return;
    state.timer = window.setTimeout(() => {
      const advanced = nextWord();
      if (advanced && state.playing) scheduleNext();
    }, wordDelay(currentWord()));
  }

  function nextWord() {
    if (!state.book || state.words.length === 0) return false;
    if (state.chapterEnded) return false;
    if (state.wordIndex < state.words.length - 1) {
      state.wordIndex += 1;
      render();
      saveSoon();
      return true;
    }
    state.chapterEnded = true;
    stopPlayback();
    render();
    saveSoon();
    return false;
  }

  function previousWord() {
    if (!state.book || state.words.length === 0) return;
    if (state.chapterEnded) {
      state.chapterEnded = false;
    } else if (state.wordIndex > 0) {
      state.wordIndex -= 1;
    }
    render();
    saveSoon();
  }

  function nextChapter() {
    if (!state.book) return;
    if (state.chapterIndex >= state.book.chapters.length - 1) {
      state.chapterEnded = true;
      stopPlayback();
      render();
      return;
    }
    state.chapterIndex += 1;
    state.wordIndex = 0;
    state.chapterEnded = false;
    stopPlayback();
    hydrateWords();
    render();
    saveSoon();
  }

  function changeWpm(delta) {
    state.wpm = Math.max(MIN_WPM, Math.min(MAX_WPM, state.wpm + delta));
    render();
    saveSoon();
    if (state.playing) scheduleNext();
  }

  function wordDelay(word) {
    const base = 60000 / state.wpm;
    if (!word) return base;
    const text = word.raw;
    const readableLen = (text.match(/[A-Za-z0-9À-ÖØ-öø-ÿ]/g) || []).length;
    let factor = 1;
    if (readableLen > 8) factor += Math.min(0.7, (readableLen - 8) * 0.055);
    if (/[.!?…]["'”’)]*$/.test(text)) factor += 0.85;
    else if (/[,;:]["'”’)]*$/.test(text)) factor += 0.45;
    else if (/[-–—()\[\]]/.test(text)) factor += 0.18;
    return Math.round(base * factor);
  }

  function render() {
    const hasBook = Boolean(state.book);
    el.importView.classList.add("hidden");
    el.readerView.classList.toggle("hidden", !hasBook);
    el.emptyView.classList.toggle("hidden", hasBook);
    if (!hasBook) {
      el.subtitle.textContent = "Nessun libro";
      return;
    }
    const chapter = currentChapter();
    el.subtitle.textContent = state.book.title;
    el.chapterLabel.textContent = `${state.chapterIndex + 1}/${state.book.chapters.length} · ${chapter.title}`;
    renderWord(currentWord() ? currentWord().raw : "—");
    const denom = Math.max(1, state.words.length - 1);
    const progress = state.chapterEnded ? 100 : Math.round((state.wordIndex / denom) * 100);
    el.progressBar.style.width = `${progress}%`;
    const finalBook = state.chapterEnded && state.chapterIndex >= state.book.chapters.length - 1;
    el.statusText.textContent = finalBook ? "Fine libro" : state.chapterEnded ? "Fine capitolo" : state.playing ? (state.holdMode ? "Hold" : "Play") : "Pausa";
    el.wpmText.textContent = `${state.wpm} wpm`;
    el.playPause.textContent = state.playing ? "Ⅱ" : "▶";
    el.chapterEnd.classList.toggle("hidden", !state.chapterEnded);
    el.nextChapterButton.disabled = state.chapterIndex >= state.book.chapters.length - 1;
    el.nextChapterButton.textContent = finalBook ? "Fine libro" : "Capitolo successivo";
  }

  function renderWord(text) {
    const pivot = pivotIndex(text);
    el.wordBefore.textContent = text.slice(0, pivot);
    el.pivot.textContent = text.charAt(pivot) || "";
    el.wordAfter.textContent = text.slice(pivot + 1);
  }

  function pivotIndex(word) {
    const readable = [];
    for (let i = 0; i < word.length; i += 1) {
      if (/[A-Za-z0-9À-ÖØ-öø-ÿ]/.test(word[i])) readable.push(i);
    }
    if (readable.length === 0) return 0;
    const len = readable.length;
    const pos = len <= 1 ? 0 : len <= 5 ? 1 : len <= 9 ? 2 : len <= 13 ? 3 : 4;
    return readable[Math.min(pos, readable.length - 1)];
  }

  function currentChapter() {
    return state.book && state.book.chapters[state.chapterIndex];
  }

  function currentWord() {
    return state.words[state.wordIndex];
  }

  async function loadState() {
    try {
      const raw = await storageGet(STORAGE_KEY);
      if (!raw) return;
      const saved = JSON.parse(raw);
      if (!saved || !saved.book) return;
      state.bookUrl = saved.bookUrl || "";
      state.document = saved.document || { book: saved.book };
      state.book = saved.book;
      state.chapterIndex = clampInt(saved.chapterIndex, 0, state.book.chapters.length - 1);
      state.wordIndex = Math.max(0, Number(saved.wordIndex || 0));
      state.wpm = clampInt(saved.wpm || DEFAULT_WPM, MIN_WPM, MAX_WPM);
    } catch (_) {
      // Ignore corrupted storage.
    }
  }

  function saveSoon() {
    if (state.saveTimer) window.clearTimeout(state.saveTimer);
    state.saveTimer = window.setTimeout(saveStateNow, 700);
  }

  async function saveStateNow() {
    if (!state.book) return;
    const payload = {
      bookUrl: state.bookUrl,
      document: state.document,
      book: state.book,
      chapterIndex: state.chapterIndex,
      wordIndex: state.wordIndex,
      wpm: state.wpm,
    };
    await storageSet(STORAGE_KEY, JSON.stringify(payload));
  }

  async function storageGet(key) {
    const store = rabbitStore();
    if (store) {
      const encoded = typeof store.getItem === "function" ? await store.getItem(key) : store[key];
      return encoded ? fromBase64(encoded) : null;
    }
    return localStorage.getItem(key);
  }

  async function storageSet(key, value) {
    const store = rabbitStore();
    if (store) {
      const encoded = toBase64(value);
      if (typeof store.setItem === "function") await store.setItem(key, encoded);
      else store[key] = encoded;
      return;
    }
    localStorage.setItem(key, value);
  }

  function rabbitStore() {
    return window.creationStorage && window.creationStorage.plain ? window.creationStorage.plain : null;
  }

  function toBase64(value) {
    return btoa(unescape(encodeURIComponent(value)));
  }

  function fromBase64(value) {
    return decodeURIComponent(escape(atob(value)));
  }

  function setImportStatus(message) {
    el.scanInfo.textContent = message;
  }

  function id(name) { return document.getElementById(name); }
  function stringValue(value) { return typeof value === "string" ? value.trim() : ""; }
  function clampInt(value, min, max) { return Math.max(min, Math.min(max, Number.parseInt(value, 10) || min)); }
  function isTyping() { return ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement && document.activeElement.tagName); }
})();
