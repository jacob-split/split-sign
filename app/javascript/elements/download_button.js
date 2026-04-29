import { target, targetable } from '@github/catalyst/lib/targetable'
import { withSafeFetchOptions } from '../lib/safe_fetch_options'

export default targetable(class extends HTMLElement {
  static [target.static] = ['defaultButton', 'loadingButton']

  connectedCallback () {
    this.addEventListener('click', () => this.downloadFiles())
  }

  toggleState () {
    this.defaultButton?.classList?.toggle('hidden')
    this.loadingButton?.classList?.toggle('hidden')
  }

  downloadFiles () {
    if (!this.dataset.src) return

    this.toggleState()

    fetch(this.dataset.src, withSafeFetchOptions()).then(async (response) => {
      if (!response.ok) throw new Error('Failed to resolve download URLs')

      const urls = await response.json()
      const isIos = /iPhone|iPad|iPod/i.test(navigator.userAgent)

      if (urls.length === 1) {
        this.openDirectUrl(urls[0])
        return
      }

      if (isIos) {
        this.downloadSafariIos(urls)
      } else {
        this.downloadUrls(urls)
      }
    }).catch(() => {
      alert('Failed to download files')
    }).finally(() => {
      this.toggleState()
    })
  }

  openDirectUrl (url) {
    window.location.assign(url)
  }

  clickLink (link) {
    document.body.appendChild(link)
    link.click()
    link.remove()
  }

  downloadUrls (urls) {
    const fileRequests = urls.map((url) => {
      return () => {
        return fetch(url).then(async (resp) => {
          if (!resp.ok) throw new Error('Failed to download file')

          const blobUrl = URL.createObjectURL(await resp.blob())
          const link = document.createElement('a')

          link.href = blobUrl
          link.setAttribute('download', decodeURI(url.split('/').pop()))

          this.clickLink(link)

          setTimeout(() => URL.revokeObjectURL(blobUrl), 1000)
        }).catch(() => {
          this.openDirectUrl(url)
        })
      }
    })

    return fileRequests.reduce(
      (prevPromise, request) => prevPromise.then(() => request()),
      Promise.resolve()
    )
  }

  downloadSafariIos (urls) {
    urls.forEach((url, index) => {
      setTimeout(() => {
        this.openDirectUrl(url)
      }, index * 250)
    })
  }
})
