import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// https://vitejs.dev/config
export default defineConfig({
  plugins: [react()],
  // Firn loads several UI panels at the same moment. Without this, the dev
  // server can discover React while those panels are loading and re-package
  // it mid-way, handing a panel mismatched copies of React that silently
  // fail to start (a blank, see-through panel). Packaging React up front
  // means every panel gets the same copy.
  optimizeDeps: {
    include: [
      'react',
      'react/jsx-dev-runtime',
      'react/jsx-runtime',
      'react-dom',
      'react-dom/client',
    ],
  },
});
