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
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken,
          Accept: 'application/json'
        },
        body: JSON.stringify({ query })
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

  updateLoadButton = () => {
    this.loadButton.disabled = !(this.merchantId && this.templateSelect.value)
  }

  loadPreview = async () => {
    const templateId = this.templateSelect.value
    if (!templateId || !this.merchantId) return

    this.loadButton.disabled = true
    this.loadButton.innerHTML = '<span class="loading loading-spinner loading-xs"></span> Loading...'
    this.hideError()

    try {
      const resp = await fetch(this.dataset.previewUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken,
          Accept: 'application/json'
        },
        body: JSON.stringify({
          merchant_id: this.merchantId,
          template_id: templateId
        })
      })

      const data = await resp.json()

      if (data.error) {
        this.showError(data.error)
        return
      }

      this.renderFields(data)
      this.updateSendSection(data, templateId)
    } catch (err) {
      this.showError('Failed to load fields: ' + err.message)
    } finally {
      this.loadButton.disabled = false
      this.loadButton.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"/><path d="M16 16h5v5"/></svg> Load Fields'
    }
  }

  renderFields = (data) => {
    const { values, agent_only_fields: agentOnly, data_paths: paths, mapping_source: source, template_fields: fields } = data
    this.fieldValues = values || {}
    this.agentOnlyFields = agentOnly || []
    this.dataPaths = paths || {}

    const tbody = this.fieldsBody
    tbody.innerHTML = ''

    let filledCount = 0
    let totalCount = 0

    fields.forEach(field => {
      const name = field.name
      if (!name) return
      totalCount++

      const value = this.fieldValues[name]
      const isAgentOnly = this.agentOnlyFields.includes(name)
      const isCheckbox = field.type === 'checkbox'

      if (value !== undefined && value !== '') filledCount++

      const tr = document.createElement('tr')
      tr.className = isAgentOnly ? 'bg-warning/10' : ''

      const tdName = document.createElement('td')
      tdName.className = 'font-medium text-sm align-top pt-3'
      tdName.innerHTML = this.escapeHtml(name)
      if (isAgentOnly) {
        tdName.innerHTML += ' <span class="badge badge-warning badge-xs ml-1">Agent</span>'
      }

      const tdValue = document.createElement('td')

      if (isCheckbox) {
        const checkbox = document.createElement('input')
        checkbox.type = 'checkbox'
        checkbox.className = 'checkbox checkbox-sm'
        checkbox.checked = value === true || value === 'true'
        checkbox.dataset.fieldName = name
        checkbox.addEventListener('change', () => {
          this.fieldValues[name] = checkbox.checked
          this.syncFormFields()
        })
        tdValue.appendChild(checkbox)
      } else {
        const input = document.createElement('input')
        input.type = 'text'
        input.className = 'input input-bordered input-sm w-full'
        input.value = value || ''
        input.placeholder = value ? '' : '(empty)'
        input.dataset.fieldName = name
        input.addEventListener('input', () => {
          this.fieldValues[name] = input.value
          this.syncFormFields()
        })
        tdValue.appendChild(input)
      }

      tr.appendChild(tdName)
      tr.appendChild(tdValue)
      tbody.appendChild(tr)
    })

    const sourceLabel = source === 'saved' ? 'saved mappings' : 'auto-mapped'
    this.fieldCount.textContent = `${filledCount}/${totalCount} fields (${sourceLabel})`
    this.fieldsSection.classList.remove('hidden')
    this.syncFormFields()
  }

  updateSendSection = (data, templateId) => {
    const templateOption = this.templateSelect.selectedOptions[0]

    this.sendMerchantName.textContent = this.merchantName
    this.sendMerchantEmail.textContent = this.merchantEmail
    this.sendTemplateName.textContent = templateOption ? templateOption.textContent.trim() : ''

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

    // Pass data_paths so the server can save mappings for reuse
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

  // Element references via data-ref attributes
  get searchInput () { return this.querySelector('[data-ref="searchInput"]') }
  get searchResults () { return this.querySelector('[data-ref="searchResults"]') }
  get templateSelect () { return this.querySelector('[data-ref="templateSelect"]') }
  get merchantInfo () { return this.querySelector('[data-ref="merchantInfo"]') }
  get merchantNameDisplay () { return this.querySelector('[data-ref="merchantNameDisplay"]') }
  get merchantEmailDisplay () { return this.querySelector('[data-ref="merchantEmailDisplay"]') }
  get clearButton () { return this.querySelector('[data-ref="clearButton"]') }
  get loadButton () { return this.querySelector('[data-ref="loadButton"]') }
  get fieldsSection () { return this.querySelector('[data-ref="fieldsSection"]') }
  get fieldsBody () { return this.querySelector('[data-ref="fieldsBody"]') }
  get fieldCount () { return this.querySelector('[data-ref="fieldCount"]') }
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
