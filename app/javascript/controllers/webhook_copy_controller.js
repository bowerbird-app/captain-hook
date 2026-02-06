import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  copy(event) {
    const input = this.inputTarget
    const button = event.currentTarget
    
    input.select()
    input.setSelectionRange(0, 99999) // For mobile devices
    
    navigator.clipboard.writeText(input.value).then(() => {
      // Show success message
      const originalHTML = button.innerHTML
      button.innerHTML = "✓ Copied!"
      button.disabled = true
      
      setTimeout(() => {
        button.innerHTML = originalHTML
        button.disabled = false
      }, 2000)
    }).catch(err => {
      console.error("Failed to copy text: ", err)
      alert("Failed to copy to clipboard")
    })
  }
}
