import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        aqua: '#00C2D1',
        deepBlue: '#2563EB',
        violet: '#7C3AED',
        pink: '#EC4899',
        'dark-bg': '#0E1525',
        'dark-surface': '#111827',
        'dark-card': '#1A1F35',
        'soft-aqua': '#E6FBFF',
        error: '#DC2626',
        success: '#16A34A',
        warning: '#F59E0B',
      },
      backgroundImage: {
        'gradient-primary': 'linear-gradient(135deg, #00C2D1 0%, #2563EB 50%, #7C3AED 100%)',
      },
      borderRadius: {
        DEFAULT: '12px',
        sm: '8px',
        lg: '16px',
      },
      fontFamily: {
        sans: [
          '-apple-system',
          'BlinkMacSystemFont',
          'Segoe UI',
          'Roboto',
          'Helvetica',
          'Arial',
          'sans-serif',
        ],
      },
    },
  },
  plugins: [],
} satisfies Config;
