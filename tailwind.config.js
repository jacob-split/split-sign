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
      },
      {
        'split-dark': {
          'color-scheme': 'dark',
          primary: '#ffffff',
          secondary: '#dddddd',
          accent: '#FF4306',
          neutral: '#2a2a2a',
          'base-100': '#1a1a1a',
          'base-200': '#222222',
          'base-300': '#333333',
          'base-content': '#e5e5e5',
          '--rounded-btn': '9999px',
          '--tab-border': '1px',
          '--tab-radius': '4px'
        }
      }
    ]
  }
}
