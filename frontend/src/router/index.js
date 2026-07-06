import { createRouter, createWebHistory } from 'vue-router';
import Home from '../views/Home.vue';
import Call from '../views/Call.vue';

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'home-en', component: Home, meta: { locale: 'en' } },
    { path: '/fa', name: 'home-fa', component: Home, meta: { locale: 'fa' } },
    { path: '/call/:uuid', name: 'call-en', component: Call, props: true, meta: { locale: 'en' } },
    { path: '/fa/call/:uuid', name: 'call-fa', component: Call, props: true, meta: { locale: 'fa' } },
  ],
});

export default router;
