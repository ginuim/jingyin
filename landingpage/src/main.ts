import { createApp } from 'vue'
import App from './App.vue'
import { initAnalytics } from './analytics'
import { router } from './router'
import './styles/main.css'

initAnalytics()
createApp(App).use(router).mount('#app')
