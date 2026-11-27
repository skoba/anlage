import { Controller } from "@hotwired/stimulus"

// 値をクリップボードに写す（skoba/anlage#192、docs/design/m3-plan.md 9.2）。
// navigator.clipboard が使えない（安全でない接続の）ときは、選択して execCommand("copy") に落とす。
// 文言は docs/demo/ui-vocabulary.md
export default class extends Controller {
  static targets = ["source", "status"]

  async copy() {
    const text = this.sourceTarget.textContent.trim()
    try {
      await navigator.clipboard.writeText(text)
    } catch (_error) {
      if (!this.fallbackCopy(text)) return this.show("写せませんでした。選んで写してください。")
    }
    this.show("写しました")
  }

  fallbackCopy(text) {
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.appendChild(area)
    area.select()
    try {
      return document.execCommand("copy")
    } catch (_error) {
      return false
    } finally {
      area.remove()
    }
  }

  show(message) {
    this.statusTarget.textContent = message
  }
}
