import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: './',
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  server: {
    host: '127.0.0.1', port: 5174, strictPort: true,
    proxy: {
      '/__bili': { target: 'https://api.bilibili.com', changeOrigin: true, rewrite: value => value.replace(/^\/__bili/, ''), headers: { Referer: 'https://www.bilibili.com', Origin: 'https://www.bilibili.com' } },
      '/__passport': { target: 'https://passport.bilibili.com', changeOrigin: true, rewrite: value => value.replace(/^\/__passport/, ''), headers: { Referer: 'https://passport.bilibili.com' } },
      '/__lyrics': { target: 'https://www.oiapi.net', changeOrigin: true, rewrite: value => value.replace(/^\/__lyrics/, '') },
    },
  },
  build: { target: 'safari15', sourcemap: false },
})
