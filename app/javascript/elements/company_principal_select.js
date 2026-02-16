export default class extends HTMLElement {
  connectedCallback () {
    this.innerHTML = '<div class="py-4 text-center text-sm opacity-60">Loading principals...</div>'
    this.fetchPrincipals()
  }

  fetchPrincipals = async () => {
    try {
      const resp = await fetch(this.dataset.listUrl, {
        headers: { Accept: 'application/json' }
      })
      const data = await resp.json()

      if (data.error) {
        this.innerHTML = `<div class="p-3 text-sm text-error">${data.error}</div>`
        return
      }

      this.principals = data.principals || []
      this.render()
    } catch (err) {
      this.innerHTML = '<div class="p-3 text-sm text-error">Failed to load company principals</div>'
    }
  }

  render () {
    const submitterCount = parseInt(this.dataset.submitterCount) || 1
    const isSingle = submitterCount === 1

    if (this.principals.length === 0) {
      this.innerHTML = `
        <div class="py-4 text-center">
          <p class="text-sm opacity-60 mb-2">No company principals configured.</p>
          <a href="/settings/company" class="btn btn-sm btn-primary">Set up Company Info</a>
        </div>
      `
      return
    }

    let html = '<div class="py-2">'
    html += '<p class="font-semibold mb-3">Select principal(s) to sign</p>'

    if (isSingle) {
      html += '<div class="space-y-2">'
      this.principals.forEach(p => {
        html += `
          <label class="flex items-center gap-3 p-3 rounded-lg border border-base-300 hover:bg-base-200 cursor-pointer">
            <input type="radio" name="company_principal" value="${p.id}" class="radio radio-sm" />
            <div>
              <span class="font-medium">${p.first_name} ${p.last_name}</span>
              <span class="text-sm opacity-60 ml-2">${p.email}</span>
            </div>
          </label>
        `
      })
      html += '</div>'
    } else {
      html += '<p class="text-sm opacity-60 mb-2">This template has ' + submitterCount + ' signer roles. Assign a principal to each role.</p>'
      html += '<div class="space-y-3" id="company-role-assignments">'

      for (let i = 0; i < submitterCount; i++) {
        html += `
          <div class="form-control">
            <label class="label"><span class="label-text font-semibold">Signer ${i + 1}</span></label>
            <select name="company_principal_${i}" class="select select-bordered w-full" data-role-index="${i}">
              <option value="">-- Select principal --</option>
              ${this.principals.map(p => `<option value="${p.id}">${p.first_name} ${p.last_name} (${p.email})</option>`).join('')}
            </select>
          </div>
        `
      }
      html += '</div>'
    }

    html += `
      <div class="mt-4">
        <button type="button" class="btn btn-primary w-full" data-ref="continueBtn">Continue</button>
      </div>
    </div>`

    this.innerHTML = html
    this.querySelector('[data-ref="continueBtn"]').addEventListener('click', this.onContinue)
  }

  onContinue = () => {
    const submitterCount = parseInt(this.dataset.submitterCount) || 1
    const redirectUrl = this.dataset.redirectUrl
    const separator = redirectUrl.includes('?') ? '&' : '?'

    if (submitterCount === 1) {
      const selected = this.querySelector('input[name="company_principal"]:checked')

      if (!selected) {
        alert('Please select a principal')
        return
      }

      window.location.href = redirectUrl + separator + 'principal_ids[]=' + encodeURIComponent(selected.value)
    } else {
      const selects = this.querySelectorAll('select[data-role-index]')
      const ids = []

      for (const sel of selects) {
        if (!sel.value) {
          alert('Please assign a principal to each signer role')
          return
        }

        ids.push(sel.value)
      }

      const qs = ids.map(id => 'principal_ids[]=' + encodeURIComponent(id)).join('&')
      window.location.href = redirectUrl + separator + qs
    }
  }
}
