import { Controller } from "@hotwired/stimulus"

const LOG_LINE_DELAY_MS = 200

// Turns the whole catalog page into an OPT dropzone: drag-in shows a
// full overlay, dropping one or more files previews them one at a time
// in the "fitting room" turbo frame (queued, so a multi-file drop
// doesn't overwhelm the visitor with N modals at once), and confirming
// registers each via a turbo-stream response that appends a card to the
// catalog without a page reload.
export default class extends Controller {
  static targets = [
    "overlay", "fittingRoom", "fileInput", "queueStatus",
    "parseLog", "parseEntries", "fittingRoomContent"
  ]
  static values = { previewUrl: String, registerUrl: String }

  connect() {
    this.dragDepth = 0
    this.queue = []
  }

  browse() {
    this.fileInputTarget.click()
  }

  async fileSelected() {
    this.enqueue(Array.from(this.fileInputTarget.files))
    this.fileInputTarget.value = ""
  }

  dragover(event) {
    event.preventDefault()
  }

  dragenter(event) {
    event.preventDefault()
    this.dragDepth++
    this.overlayTarget.classList.add("visible")
  }

  dragleave(event) {
    event.preventDefault()
    this.dragDepth--
    if (this.dragDepth <= 0) this.overlayTarget.classList.remove("visible")
  }

  async drop(event) {
    event.preventDefault()
    this.dragDepth = 0
    this.overlayTarget.classList.remove("visible")

    this.enqueue(Array.from(event.dataTransfer.files))
  }

  async enqueue(files) {
    if (files.length === 0) return

    this.queue.push(...files)
    if (!this.pendingFile) await this.previewNext()
  }

  async previewNext() {
    const file = this.queue.shift()
    if (!file) {
      this.pendingFile = null
      this.fittingRoomTarget.innerHTML = ""
      this.queueStatusTarget.textContent = ""
      return
    }

    this.queueStatusTarget.textContent = this.queue.length > 0
      ? `残り${this.queue.length}件を後ほど確認します`
      : ""
    await this.preview(file)
  }

  async preview(file) {
    this.pendingFile = file

    const response = await fetch(this.previewUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrfToken(), Accept: "text/html" },
      body: this.formDataFor(file)
    })
    this.fittingRoomTarget.innerHTML = await response.text()
    await this.revealParseLog()
  }

  // Plays back the (already-complete) parse result as a "detecting
  // archetype N..." log, then reveals the fitting room's form preview.
  // Not a live progress report from the server -- the parse itself is
  // fast; this paces out its real result for the "a model just appeared"
  // effect the demo is going for.
  async revealParseLog() {
    if (!this.hasParseEntriesTarget || !this.hasParseLogTarget) return

    const entries = JSON.parse(this.parseEntriesTarget.textContent)
    for (const entry of entries) {
      const line = document.createElement("p")
      line.textContent = `archetype検出: ${entry.concept}（${entry.field_count}フィールド）`
      this.parseLogTarget.appendChild(line)
      await this.delay(LOG_LINE_DELAY_MS)
    }

    if (this.hasFittingRoomContentTarget) this.fittingRoomContentTarget.hidden = false
  }

  delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  async register(event) {
    event.preventDefault()
    if (!this.pendingFile) return

    const response = await fetch(this.registerUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrfToken(), Accept: "text/vnd.turbo-stream.html" },
      body: this.formDataFor(this.pendingFile)
    })
    Turbo.renderStreamMessage(await response.text())
    await this.previewNext()
  }

  async discard() {
    await this.previewNext()
  }

  formDataFor(file) {
    const formData = new FormData()
    formData.append("file", file)
    return formData
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
