export const getCsrfToken = () => document.querySelector('meta[name="csrf-token"]')?.content || ''

export const withSafeFetchOptions = (options = {}) => {
  const headers = new Headers(options.headers || {})
  const csrfToken = getCsrfToken()

  if (csrfToken && !headers.has('X-CSRF-Token')) {
    headers.set('X-CSRF-Token', csrfToken)
  }

  return {
    credentials: 'same-origin',
    ...options,
    headers
  }
}
