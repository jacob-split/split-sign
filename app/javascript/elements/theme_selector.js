class ThemeSelector extends HTMLElement {
  connectedCallback() {
    this.updateActive();
    this.querySelectorAll('[data-theme-value]').forEach(el => {
      el.addEventListener('click', (e) => this.set(e));
    });
  }

  set(event) {
    const theme = event.currentTarget.dataset.themeValue;
    localStorage.setItem('theme', theme);
    this.apply(theme);
    this.updateActive();
  }

  apply(theme) {
    const doc = document.documentElement;
    if (theme === 'system') {
      const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      doc.setAttribute('data-theme', dark ? 'dark' : 'split');
    } else {
      doc.setAttribute('data-theme', theme);
    }
  }

  updateActive() {
    const current = localStorage.getItem('theme') || 'system';
    this.querySelectorAll('[data-theme-value]').forEach(el => {
      if (el.dataset.themeValue === current) {
        el.classList.add('bg-base-300');
      } else {
        el.classList.remove('bg-base-300');
      }
    });
  }
}

if (!window.customElements.get('theme-selector')) {
  window.customElements.define('theme-selector', ThemeSelector);
}
