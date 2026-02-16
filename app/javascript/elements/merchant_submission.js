const FIELD_TYPE_ICONS = {
  text: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7v-2h13v2"/><path d="M10 5v14"/><path d="M12 19h-4"/><path d="M15 13v-1h6v1"/><path d="M18 12v7"/><path d="M17 19h2"/></svg>',
  number: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10l2 -2v8"/><path d="M9 8h3a1 1 0 0 1 1 1v2a1 1 0 0 1 -1 1h-2a1 1 0 0 0 -1 1v2a1 1 0 0 0 1 1h3"/><path d="M17 8h2.5a1.5 1.5 0 0 1 1.5 1.5v1a1.5 1.5 0 0 1 -1.5 1.5h-1.5h1.5a1.5 1.5 0 0 1 1.5 1.5v1a1.5 1.5 0 0 1 -1.5 1.5h-2.5"/></svg>',
  date: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5m0 2a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2z"/><path d="M16 3v4"/><path d="M8 3v4"/><path d="M4 11h16"/><path d="M8 15h2v2h-2z"/></svg>',
  checkbox: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3l8 -8"/><path d="M20 12v6a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2h9"/></svg>',
  select: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3m0 2a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2z"/><path d="M9 11l3 3l3 -3"/></svg>',
  radio: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3"/></svg>',
  multiple: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12l5 5l10 -10"/><path d="M7 12l5 5l10 -10"/></svg>',
  cells: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4m0 2a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2z"/><path d="M10 4v16"/><path d="M14 4v16"/></svg>',
  phone: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 4h4l2 5l-2.5 1.5a11 11 0 0 0 5 5l1.5 -2.5l5 2v4a2 2 0 0 1 -2 2a16 16 0 0 1 -15 -15a2 2 0 0 1 2 -2"/><path d="M15 6l2 2l4 -4"/></svg>'
}

export default class extends HTMLElement {
  connectedCallback () {
    this.merchantId = null
    this.merchantName = ''
    this.merchantEmail = ''
    this.searchTimeout = null
    this.fieldValues = {}
    this.agentOnlyFields = []
    this.dataPaths = {}

    this.searchInput.addEventListener('input', this.onSearchInput)
    this.templateSelect.addEventListener('change', this.onTemplateChange)
    this.loadButton.addEventListener('click', this.loadPreview)
    this.clearButton.addEventListener('click', this.clearMerchant)
    this.changeButton.addEventListener('click', this.onChangeClick)

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
        this.showError(merchants.error)
        return
      }

      this.renderSearchResults(merchants)
    } catch (err) {
      this.showError('Search failed: ' + err.message)
    }
  }

  renderSearchResults = (merchants) => {
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
    this.merchantId = merchant.id
    this.merchantName = merchant.business_name
    this.merchantEmail = merchant.email

    this.searchInput.classList.add('hidden')
    this.merchantInfo.classList.remove('hidden')
    this.merchantNameDisplay.textContent = merchant.dba_name || merchant.business_name
    this.merchantEmailDisplay.textContent = merchant.email
    this.searchResults.classList.add('hidden')

    this.updateLoadButton()
  }

  clearMerchant = () => {
    this.merchantId = null
    this.merchantName = ''
    this.merchantEmail = ''

    this.searchInput.value = ''
    this.searchInput.classList.remove('hidden')
    this.merchantInfo.classList.add('hidden')

    this.fieldsSection.classList.add('hidden')
    this.sendSection.classList.add('hidden')

    this.updateLoadButton()
  }

  onTemplateChange = () => {
    this.fieldsSection.classList.add('hidden')
    this.sendSection.classList.add('hidden')
    this.updateLoadButton()
  }

  onChangeClick = () => {
    this.fieldsSection.classList.add('hidden')
    this.sendSection.classList.add('hidden')
    this.selectionSection.classList.remove('hidden')
  }

  updateLoadButton = () => {
    this.loadButton.disabled = !(this.merchantId && this.templateSelect.value)
  }

  loadPreview = async () => {
    const templateId = this.templateSelect.value
    if (!templateId || !this.merchantId) return

    this.loadButton.disabled = true
    this.loadButton.textContent = 'Loading...'
    this.hideError()

    try {
      const resp = await fetch(this.dataset.previewUrl, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.csrfToken,
          Accept: 'application/json'
        },
        body: new URLSearchParams({
          merchant_id: this.merchantId,
          template_id: templateId
        })
      })

      const data = await resp.json()

      if (data.error) {
        this.showError(data.error)
        return
      }

      this.renderDocumentPages(data.document_pages || [])
      this.renderFields(data)
      this.updateSendSection(data, templateId)
    } catch (err) {
      this.showError('Failed to load fields: ' + err.message)
    } finally {
      this.loadButton.disabled = false
      this.loadButton.textContent = 'Load Fields'
    }
  }

  renderDocumentPages = (pages) => {
    const container = this.documentPages
    container.innerHTML = ''

    if (!pages.length) {
      container.innerHTML = '<div class="text-center py-12 text-sm opacity-40">No document preview available</div>'
      return
    }

    pages.forEach((page, index) => {
      const wrapper = document.createElement('div')
      wrapper.className = 'relative rounded border border-base-200 overflow-hidden bg-white'

      const img = document.createElement('img')
      img.src = page.url
      img.loading = 'lazy'
      img.className = 'w-full'
      img.alt = `Page ${index + 1}`

      const badge = document.createElement('div')
      badge.className = 'absolute top-2 left-2 badge badge-neutral badge-sm opacity-70'
      badge.textContent = index + 1

      wrapper.appendChild(img)
      wrapper.appendChild(badge)
      container.appendChild(wrapper)
    })
  }

  renderFields = (data) => {
    const { values, agent_only_fields: agentOnly, data_paths: paths, mapping_source: source, template_fields: fields } = data
    this.fieldValues = values || {}
    this.agentOnlyFields = agentOnly || []
    this.dataPaths = paths || {}

    const container = this.fieldsBody
    container.innerHTML = ''

    let filledCount = 0
    let totalCount = 0

    fields.forEach(field => {
      const name = field.name
      if (!name) return
      totalCount++

      const value = this.fieldValues[name]
      const isAgentOnly = this.agentOnlyFields.includes(name)
      const isCheckbox = field.type === 'checkbox'
      const isFilled = value !== undefined && value !== '' && value !== null

      if (isFilled) filledCount++

      const card = document.createElement('div')
      card.className = 'border border-base-300 rounded relative group'
      if (isAgentOnly) {
        card.style.backgroundColor = 'rgba(255, 183, 0, 0.05)'
      }

      // Header: icon + name + badge + status
      const header = document.createElement('div')
      header.className = 'flex items-center justify-between p-1.5'

      const left = document.createElement('div')
      left.className = 'flex items-center gap-1.5 min-w-0'

      const iconSpan = document.createElement('span')
      iconSpan.className = 'flex-shrink-0 opacity-50'
      iconSpan.innerHTML = FIELD_TYPE_ICONS[field.type] || FIELD_TYPE_ICONS.text
      left.appendChild(iconSpan)

      const nameSpan = document.createElement('span')
      nameSpan.className = 'text-sm truncate'
      nameSpan.textContent = name
      left.appendChild(nameSpan)

      if (isAgentOnly) {
        const badge = document.createElement('span')
        badge.className = 'badge badge-warning badge-xs flex-shrink-0'
        badge.textContent = 'Agent'
        left.appendChild(badge)
      }

      header.appendChild(left)

      const statusDot = document.createElement('span')
      statusDot.className = isFilled
        ? 'w-2 h-2 rounded-full bg-success flex-shrink-0'
        : 'w-2 h-2 rounded-full bg-base-300 flex-shrink-0'
      header.appendChild(statusDot)

      card.appendChild(header)

      // Input area
      const inputArea = document.createElement('div')
      inputArea.className = 'px-1.5 pb-1.5'

      if (isCheckbox) {
        const label = document.createElement('label')
        label.className = 'flex items-center gap-2 cursor-pointer'
        const cb = document.createElement('input')
        cb.type = 'checkbox'
        cb.className = 'checkbox checkbox-sm'
        cb.checked = value === true || value === 'true'
        cb.dataset.fieldName = name
        cb.addEventListener('change', () => {
          this.fieldValues[name] = cb.checked
          this.syncFormFields()
        })
        label.appendChild(cb)
        inputArea.appendChild(label)
      } else {
        const input = document.createElement('input')
        input.type = 'text'
        input.className = 'input input-bordered input-sm w-full !h-8 text-sm'
        input.value = value || ''
        input.placeholder = '(empty)'
        input.dataset.fieldName = name
        input.addEventListener('input', () => {
          this.fieldValues[name] = input.value
          this.syncFormFields()
        })
        inputArea.appendChild(input)
      }

      card.appendChild(inputArea)
      container.appendChild(card)
    })

    const sourceLabel = source === 'saved' ? 'saved mappings' : 'auto-mapped'
    this.fieldCount.textContent = `${filledCount}/${totalCount} (${sourceLabel})`

    // Transition: hide selection, show fields + send
    this.selectionSection.classList.add('hidden')
    this.fieldsSection.classList.remove('hidden')

    // Populate summary bar
    const templateOption = this.templateSelect.selectedOptions[0]
    this.summaryTemplateName.textContent = templateOption ? templateOption.textContent.trim() : ''
    this.summaryMerchantName.textContent = this.merchantName
    this.summaryMerchantEmail.textContent = this.merchantEmail

    this.syncFormFields()
  }

  updateSendSection = (data, templateId) => {
    this.formTemplateId.value = templateId
    this.formMerchantId.value = this.merchantId
    this.formMerchantName.value = this.merchantName
    this.formMerchantEmail.value = this.merchantEmail

    this.syncFormFields()
    this.sendSection.classList.remove('hidden')
  }

  syncFormFields = () => {
    const container = this.formFieldsContainer
    container.innerHTML = ''

    Object.entries(this.fieldValues).forEach(([name, value]) => {
      if (value === undefined || value === null) return
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = `field_values[${name}]`
      input.value = String(value)
      container.appendChild(input)
    })

    this.agentOnlyFields.forEach(name => {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = 'agent_only_fields[]'
      input.value = name
      container.appendChild(input)
    })

    Object.entries(this.dataPaths).forEach(([name, path]) => {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = `data_paths[${name}]`
      input.value = path
      container.appendChild(input)
    })
  }

  escapeHtml = (str) => {
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  }

  showError = (message) => {
    this.errorAlert.classList.remove('hidden')
    this.errorMessage.textContent = message
  }

  hideError = () => {
    this.errorAlert.classList.add('hidden')
  }

  get csrfToken () {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }

  // Element references
  get selectionSection () { return this.querySelector('[data-ref="selectionSection"]') }
  get searchInput () { return this.querySelector('[data-ref="searchInput"]') }
  get searchResults () { return this.querySelector('[data-ref="searchResults"]') }
  get templateSelect () { return this.querySelector('[data-ref="templateSelect"]') }
  get merchantInfo () { return this.querySelector('[data-ref="merchantInfo"]') }
  get merchantNameDisplay () { return this.querySelector('[data-ref="merchantNameDisplay"]') }
  get merchantEmailDisplay () { return this.querySelector('[data-ref="merchantEmailDisplay"]') }
  get clearButton () { return this.querySelector('[data-ref="clearButton"]') }
  get loadButton () { return this.querySelector('[data-ref="loadButton"]') }
  get changeButton () { return this.querySelector('[data-ref="changeButton"]') }
  get fieldsSection () { return this.querySelector('[data-ref="fieldsSection"]') }
  get fieldsBody () { return this.querySelector('[data-ref="fieldsBody"]') }
  get fieldCount () { return this.querySelector('[data-ref="fieldCount"]') }
  get summaryTemplateName () { return this.querySelector('[data-ref="summaryTemplateName"]') }
  get summaryMerchantName () { return this.querySelector('[data-ref="summaryMerchantName"]') }
  get summaryMerchantEmail () { return this.querySelector('[data-ref="summaryMerchantEmail"]') }
  get documentPreview () { return this.querySelector('[data-ref="documentPreview"]') }
  get documentPages () { return this.querySelector('[data-ref="documentPages"]') }
  get sendSection () { return this.querySelector('[data-ref="sendSection"]') }
  get sendMerchantName () { return this.querySelector('[data-ref="sendMerchantName"]') }
  get sendMerchantEmail () { return this.querySelector('[data-ref="sendMerchantEmail"]') }
  get sendTemplateName () { return this.querySelector('[data-ref="sendTemplateName"]') }
  get formTemplateId () { return this.querySelector('[data-ref="formTemplateId"]') }
  get formMerchantId () { return this.querySelector('[data-ref="formMerchantId"]') }
  get formMerchantName () { return this.querySelector('[data-ref="formMerchantName"]') }
  get formMerchantEmail () { return this.querySelector('[data-ref="formMerchantEmail"]') }
  get formFieldsContainer () { return this.querySelector('[data-ref="formFieldsContainer"]') }
  get errorAlert () { return this.querySelector('[data-ref="errorAlert"]') }
  get errorMessage () { return this.querySelector('[data-ref="errorMessage"]') }
}
