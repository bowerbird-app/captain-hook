import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  copy() {
    const input = this.inputTarget
    input.select()
    input.setSelectionRange(0, 99999) // For mobile devices
    
    navigator.clipboard.writeText(input.value).then(() => {
      // Optional: Show a temporary success message
      const originalText = this.element.querySelector("button").textContent
      this.element.querySelector("button").textContent = "✓ Copied!"
      
      setTimeout(() => {
        this.element.querySelector("button").textContent = originalText
      }, 2000)
    }).catch(err => {
      console.error("Failed to copy text: ", err)
      // Fallback for older browsers
      document.execCommand("copy")
    })
  }
}
