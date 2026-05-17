(() => {
  const creationUrlInput = document.getElementById("creationUrl");
  const creationQr = document.getElementById("creationQr");
  const creationPayload = document.getElementById("creationPayload");
  const bookForm = document.getElementById("bookForm");
  const bookUrlInput = document.getElementById("bookUrl");
  const bookQr = document.getElementById("bookQr");
  const bookQrWrap = document.getElementById("bookQrWrap");

  const creationUrl = new URL("./?app=1", window.location.href).href;
  const installPayload = {
    title: "Pizza Reader",
    url: creationUrl,
    description: "Reader one-word-at-a-time per libri .pizzabook.json",
    themeColor: "#fff4df",
  };

  creationUrlInput.value = creationUrl;
  creationPayload.textContent = JSON.stringify(installPayload, null, 2);
  setQrImage(creationQr, JSON.stringify(installPayload));

  const params = new URLSearchParams(window.location.search);
  const initialBookUrl = params.get("book");
  if (initialBookUrl) {
    bookUrlInput.value = initialBookUrl;
    renderBookQr(initialBookUrl);
  }

  bookForm.addEventListener("submit", (event) => {
    event.preventDefault();
    renderBookQr(bookUrlInput.value.trim());
  });

  function renderBookQr(rawUrl) {
    try {
      const url = new URL(rawUrl);
      if (url.protocol !== "https:" && !(url.protocol === "http:" && url.hostname === "localhost")) {
        throw new Error("URL non supportato");
      }
      const readerUrl = new URL("./?app=1", window.location.href);
      readerUrl.searchParams.set("book", url.href);
      const bookPayload = {
        title: "Pizza Reader",
        url: readerUrl.href,
        description: "Apri Pizza Reader e importa questo libro",
        themeColor: "#fff4df",
      };
      setQrImage(bookQr, JSON.stringify(bookPayload));
      bookQrWrap.classList.remove("empty");
      const nextUrl = new URL(window.location.href);
      nextUrl.searchParams.set("book", url.href);
      window.history.replaceState(null, "", nextUrl.href);
    } catch (_) {
      window.alert("Inserisci un URL HTTPS valido del file .pizzabook.json.");
    }
  }

  function setQrImage(img, data) {
    img.src = "https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=8&data=" + encodeURIComponent(data);
  }
})();
