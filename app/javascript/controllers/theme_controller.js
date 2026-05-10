import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]

  connect() {
    this.updateActive()
  }

  set(event) {
    const theme = event.currentTarget.dataset.themeValue
    localStorage.setItem('theme', theme)
    this.apply(theme)
    this.updateActive()
  }

  apply(theme) {
    const doc = document.documentElement
    if (theme === 'system') {
      const dark = window.matchMedia('(prefers-color-scheme: dark)').matches
      doc.setAttribute('data-theme', dark ? 'dark' : 'split')
    } else {
      doc.setAttribute('data-theme', theme)
    }
  }

  updateActive() {
    const current = localStorage.getItem('theme') || 'system'
    this.element.querySelectorAll('[data-theme-value]').forEach(el => {
      if (el.dataset.themeValue === current) {
        el.classList.add('bg-base-300')
      } else {
        el.classList.remove('bg-base-300')
      }
    })
  }
}
