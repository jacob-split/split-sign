module.exports = {
  plugins: [
    require('daisyui')
  ],
  daisyui: {
    themes: [
      {
        split: {
          'color-scheme': 'light',
          primary: '#111111',
          secondary: '#222222',
          accent: '#FF4306',
          neutral: '#111111',
          'base-100': '#ffffff',
          'base-200': '#F5F5F5',
          'base-300': '#E5E5E5',
          'base-content': '#111111',
          '--rounded-btn': '9999px',
          '--tab-border': '1px',
          '--tab-radius': '4px'
        }
      }
    ]
  }
}
