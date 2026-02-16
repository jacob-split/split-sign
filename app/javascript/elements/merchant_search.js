export default class extends HTMLElement {
  connectedCallback () {
    this.searchTimeout = null

    this.innerHTML = `
      <div class="form-control w-full">
        <label class="label"><span class="label-text font-semibold">Search for a merchant</span></label>
        <input type="text" data-ref="searchInput" placeholder="Type business name or email..."
               class="input input-bordered w-full" autocomplete="off" />
        <div data-ref="searchResults" class="hidden mt-1 border border-base-300 rounded-lg bg-base-100 shadow-lg max-h-60 overflow-auto"></div>
      </div>
    `

    this.searchInput.addEventListener('input', this.onSearchInput)
    document.addEventListener('click', this.onDocumentClick)
  }

  disconnectedCallback () {
    document.removeEventListener('click', this.onDocumentClick)
  }

  onDocumentClick = (e) => {
    if (!this.searchResults.contains(e.target) && e.target !== this.searchInput) {
      this.searchResults.classList.add('hidden')
    }
  }

  onSearchInput = () => {
    clearTimeout(this.searchTimeout)
    const query = this.searchInput.value.trim()

    if (query.length < 2) {
      this.searchResults.classList.add('hidden')
      return
    }

    this.searchTimeout = setTimeout(() => {
      this.performSearch(query)
    }, 250)
  }

  performSearch = async (query) => {
    try {
      const resp = await fetch(this.dataset.searchUrl, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.csrfToken,
          Accept: 'application/json'
        },
        body: new URLSearchParams({ query })
      })

      const merchants = await resp.json()

      if (merchants.error) {
        this.searchResults.innerHTML = '<div class="p-3 text-sm text-error">' + merchants.error + '</div>'
        this.searchResults.classList.remove('hidden')
        return
      }

      this.renderResults(merchants)
    } catch (err) {
      this.searchResults.innerHTML = '<div class="p-3 text-sm text-error">Search failed</div>'
      this.searchResults.classList.remove('hidden')
    }
  }

  renderResults = (merchants) => {
    this.searchResults.innerHTML = ''

    if (merchants.length === 0) {
      this.searchResults.innerHTML = '<div class="p-3 text-sm opacity-60">No merchants found</div>'
      this.searchResults.classList.remove('hidden')
      return
    }

    merchants.forEach(m => {
      const div = document.createElement('div')
      div.className = 'p-3 hover:bg-base-200 cursor-pointer text-sm border-b border-base-200 last:border-0'
      div.textContent = m.label
      div.addEventListener('click', () => this.selectMerchant(m))
      this.searchResults.appendChild(div)
    })

    this.searchResults.classList.remove('hidden')
  }

  selectMerchant = (merchant) => {
    const redirectUrl = this.dataset.redirectUrl
    const separator = redirectUrl.includes('?') ? '&' : '?'

    window.location.href = redirectUrl + separator + 'merchant_id=' + encodeURIComponent(merchant.id)
  }

  get csrfToken () {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }

  get searchInput () { return this.querySelector('[data-ref="searchInput"]') }
  get searchResults () { return this.querySelector('[data-ref="searchResults"]') }
}
