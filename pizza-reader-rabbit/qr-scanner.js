/* global BarcodeDetector */
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
    }

    async start() {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        throw new Error("Camera non disponibile in questo browser.");
      }
      if (!("BarcodeDetector" in window)) {
        throw new Error("BarcodeDetector non disponibile: usa l'URL manuale.");
      }
      this.detector = new BarcodeDetector({ formats: ["qr_code"] });
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: "environment" } },
        audio: false,
      });
      this.video.srcObject = this.stream;
      this.video.classList.remove("hidden");
      await this.video.play();
      this.running = true;
      this.onStatus("Scanner attivo");
      this.loop();
    }

    async loop() {
      if (!this.running || !this.detector) return;
      try {
        const codes = await this.detector.detect(this.video);
        const value = codes && codes[0] && (codes[0].rawValue || codes[0].displayValue);
        if (value) {
          this.onCode(value);
          return;
        }
      } catch (error) {
        this.onStatus(error.message || "Errore scanner");
      }
      this.timer = window.setTimeout(() => this.loop(), 350);
    }

    stop() {
      this.running = false;
      if (this.timer) window.clearTimeout(this.timer);
      this.timer = null;
      if (this.stream) {
        for (const track of this.stream.getTracks()) track.stop();
      }
      this.stream = null;
      this.video.pause();
      this.video.srcObject = null;
      this.video.classList.add("hidden");
    }
  }

  window.PizzaQrScanner = QrScanner;
})();
