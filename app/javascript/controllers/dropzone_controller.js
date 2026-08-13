import { Controller } from "@hotwired/stimulus"

// Turns the whole catalog page into an OPT dropzone: drag-in shows a
// full overlay, dropping a file previews it in the "fitting room" turbo
// frame, and confirming registers it via a turbo-stream response that
// appends a card to the catalog without a page reload.
export default class extends Controller {
  static targets = ["overlay", "fittingRoom", "fileInput"]
  static values = { previewUrl: String, registerUrl: String }

  connect() {
    this.dragDepth = 0
  }

  browse() {
    this.fileInputTarget.click()
  }

  async fileSelected() {
    const [ file ] = Array.from(this.fileInputTarget.files)
    if (file) await this.preview(file)
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

    const [ file ] = Array.from(event.dataTransfer.files)
    if (file) await this.preview(file)
  }

  async preview(file) {
    this.pendingFile = file

    const response = await fetch(this.previewUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrfToken(), Accept: "text/html" },
      body: this.formDataFor(file)
    })
    this.fittingRoomTarget.innerHTML = await response.text()
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
    this.discard()
  }

  discard() {
    this.fittingRoomTarget.innerHTML = ""
    this.pendingFile = null
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
