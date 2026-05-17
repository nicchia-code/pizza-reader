/* global BarcodeDetector, jsQR */
(() => {
  class QrScanner {
    constructor(video, onCode, onStatus) {
      this.video = video;
      this.onCode = onCode;
      this.onStatus = onStatus || (() => {});
      this.stream = null;
      this.detector = null;
      this.timer = null;
      this.running = false;
      this.canvas = document.createElement("canvas");
      this.context = this.canvas.getContext("2d", { willReadFrequently: true });
      this.scanWithBarcodeDetector = false;
    }

    async start() {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        throw new Error("Camera non disponibile. Apri la pagina via HTTPS sul Rabbit.");
      }

      this.scanWithBarcodeDetector = "BarcodeDetector" in window;
      if (this.scanWithBarcodeDetector) {
        try {
          this.detector = new BarcodeDetector({ formats: ["qr_code"] });
        } catch (_) {
          this.scanWithBarcodeDetector = false;
          this.detector = null;
        }
      }

      if (!this.scanWithBarcodeDetector && typeof jsQR !== "function") {
        throw new Error("Scanner QR non disponibile su questo browser.");
      }

      this.stream = await this.openCamera();
      this.video.srcObject = this.stream;
      this.video.setAttribute("playsinline", "");
      this.video.muted = true;
      this.video.classList.remove("hidden");
      await this.video.play();
      this.running = true;
      this.onStatus(this.scanWithBarcodeDetector ? "Scanner attivo" : "Scanner attivo (compatibilità)");
      this.loop();
    }

    async openCamera() {
      const attempts = [
        { video: { facingMode: { exact: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false },
        { video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false },
        { video: true, audio: false },
      ];
      let lastError = null;
      for (const constraints of attempts) {
        try {
          return await navigator.mediaDevices.getUserMedia(constraints);
        } catch (error) {
          lastError = error;
        }
      }
      throw new Error(cameraErrorMessage(lastError));
    }

    async loop() {
      if (!this.running) return;
      try {
        const value = this.scanWithBarcodeDetector
          ? await this.detectWithBarcodeDetector()
          : this.detectWithJsQr();
        if (value) {
          this.onCode(value);
          return;
        }
      } catch (error) {
        this.onStatus(error.message || "Errore scanner");
      }
      this.timer = window.setTimeout(() => this.loop(), 180);
    }

    async detectWithBarcodeDetector() {
      if (!this.detector || this.video.readyState < 2) return "";
      const codes = await this.detector.detect(this.video);
      return codes && codes[0] && (codes[0].rawValue || codes[0].displayValue) || "";
    }

    detectWithJsQr() {
      if (!this.context || this.video.readyState < 2) return "";
      const width = this.video.videoWidth || this.video.clientWidth;
      const height = this.video.videoHeight || this.video.clientHeight;
      if (!width || !height) return "";
      this.canvas.width = width;
      this.canvas.height = height;
      this.context.drawImage(this.video, 0, 0, width, height);
      const imageData = this.context.getImageData(0, 0, width, height);
      const code = jsQR(imageData.data, imageData.width, imageData.height, {
        inversionAttempts: "dontInvert",
      });
      return code && code.data || "";
    }

    stop() {
      this.running = false;
      if (this.timer) window.clearTimeout(this.timer);
      this.timer = null;
      if (this.stream) {
        for (const track of this.stream.getTracks()) track.stop();
      }
      this.stream = null;
      this.detector = null;
      this.video.pause();
      this.video.srcObject = null;
      this.video.classList.add("hidden");
    }
  }

  function cameraErrorMessage(error) {
    const name = error && error.name;
    if (name === "NotAllowedError" || name === "PermissionDeniedError") {
      return "Permesso camera negato. Abilita la camera e riprova.";
    }
    if (name === "NotFoundError" || name === "DevicesNotFoundError") {
      return "Nessuna camera trovata.";
    }
    if (name === "NotReadableError" || name === "TrackStartError") {
      return "Camera occupata o non leggibile. Chiudi altre app e riprova.";
    }
    if (name === "OverconstrainedError" || name === "ConstraintNotSatisfiedError") {
      return "Camera non compatibile con i vincoli richiesti.";
    }
    return (error && error.message) || "Impossibile avviare la camera.";
  }

  window.PizzaQrScanner = QrScanner;
})();
