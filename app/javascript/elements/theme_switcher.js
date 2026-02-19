export default class extends HTMLElement {
  connectedCallback () {
    this.preference = localStorage.getItem('split-theme-preference') || 'system'
    this.mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    this.onSystemChange = () => {
      if (this.preference === 'system') this.applyTheme()
    }
    this.mediaQuery.addEventListener('change', this.onSystemChange)
    this.updateButtons()

    this.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-theme-mode]')
      if (!btn) return
      this.preference = btn.dataset.themeMode
      localStorage.setItem('split-theme-preference', this.preference)
      this.applyTheme()
      this.updateButtons()
    })
  }

  disconnectedCallback () {
    if (this.mediaQuery) {
      this.mediaQuery.removeEventListener('change', this.onSystemChange)
    }
  }

  applyTheme () {
    let theme
    if (this.preference === 'dark') {
      theme = 'split-dark'
    } else if (this.preference === 'light') {
      theme = 'split'
    } else {
      theme = this.mediaQuery.matches ? 'split-dark' : 'split'
    }
    document.documentElement.setAttribute('data-theme', theme)
  }

  updateButtons () {
    this.querySelectorAll('[data-theme-mode]').forEach((btn) => {
      const isActive = btn.dataset.themeMode === this.preference
      btn.classList.toggle('bg-base-content', isActive)
      btn.classList.toggle('text-base-100', isActive)
      btn.classList.toggle('text-base-content', !isActive)
    })
  }
}
