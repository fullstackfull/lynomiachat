<script setup>
import { ref, onMounted } from 'vue';

const isOpen = ref(false);
const isScrolled = ref(false);

const toggleMenu = () => {
  isOpen.value = !isOpen.value;
  document.body.style.overflow = isOpen.value ? 'hidden' : '';
};

const closeMenu = () => {
  isOpen.value = false;
  document.body.style.overflow = '';
};

onMounted(() => {
  window.addEventListener('scroll', () => {
    isScrolled.value = window.scrollY > 60;
  });

  window.addEventListener('resize', () => {
    if (window.innerWidth > 1024) closeMenu();
  });
});
</script>

<template>
  <nav
    class="top-nav"
    :class="{ scrolled: isScrolled }"
    id="topNav"
  >
    <!-- Brand -->
    <a href="#" class="nav-brand">
      <img
        src="https://lynomia.com/img/logo.png"
        style="width:9rem;display:inline-block"
      />
      <span class="brand-text">Chat</span>
    </a>

    <!-- Links -->
    <ul class="nav-links">
      <li><a href="https://lynomia.com">Home</a></li>
      <li><a href="https://lynomia.com/terms">Terms</a></li>
      <li><a href="https://lynomia.com/privacy">Privacy</a></li>
      <li><a href="https://lynomia.com/contact">Contact Us</a></li>
      <li><a href="https://lynomia.com/about_us">About Us</a></li>

      <!-- PHP logic replaced -->
  
    </ul>

    <!-- CTA -->
    <a href="#pricing" class="nav-cta">Get Started</a>

    <!-- Toggle -->
    <button
      class="nav-toggle"
      :class="{ active: isOpen }"
      @click="toggleMenu"
      aria-label="Toggle menu"
    >
      <span class="toggle-bar"></span>
      <span class="toggle-bar"></span>
    </button>
  </nav>

  <!-- Mobile Menu -->
  <div class="mobile-menu" :class="{ open: isOpen }">
    <div class="mobile-menu-inner">
      <div class="mobile-menu-links">

        <a class="mobile-menu-link" @click="closeMenu" href="/">Home</a>
        <a class="mobile-menu-link" @click="closeMenu" href="/terms">Terms</a>
        <a class="mobile-menu-link" @click="closeMenu" href="/privacy">Privacy</a>
        <a class="mobile-menu-link" @click="closeMenu" href="/contact">Contact Us</a>
        <a class="mobile-menu-link" @click="closeMenu" href="/about_us">About Us</a>

     
      </div>
    </div>
  </div>
</template>

<style scoped>
.top-nav {
  position: fixed; top: 0; left: 0; right: 0; z-index: 600;
  display: flex; justify-content: space-between; align-items: center;
  padding: 24px 40px;
  transition: background 0.8s var(--silk-ease), padding 0.8s var(--silk-ease);
  background: #07070730;
}

.top-nav.scrolled {
  background: rgba(15, 17, 21, 0.47);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  padding: 16px 40px;
}
.nav-brand {
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: white;
  text-decoration: none;
}

.nav-brand span {
  font-weight: bolder;
  color: var(--slate-warm);
  margin-left: 4px;
}
.nav-links {
  display: flex;
  gap: 32px;
  list-style: none;
  align-items: center;
}

.nav-links a {
  font-size: 10px;
  font-weight: 500;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--slate-warm);
  text-decoration: none;
  position: relative;
  padding: 14px 0 6px;
  transition: color 0.8s var(--silk-ease);
}

.nav-links a:hover { color: var(--ivory); }

.nav-links a.active { color: var(--ivory-muted); }

.nav-links a::after {
  content: '';
  position: absolute;
  top: 0; left: 50%;
  width: 6px; height: 6px;
  border-right: 1px solid var(--silver);
  border-bottom: 1px solid var(--silver);
  transform: translateX(-50%) rotate(45deg) translateY(-8px);
  opacity: 0;
  transition: transform 0.8s var(--silk-ease), opacity 0.6s var(--silk-ease);
  pointer-events: none;
}

.nav-links a:hover::after {
  opacity: 0.7;
  transform: translateX(-50%) rotate(45deg) translateY(0);
}

.nav-links a.active::after {
  opacity: 0.4;
  transform: translateX(-50%) rotate(45deg) translateY(0);
}

.nav-cta {
  padding: 10px 28px;
  border-radius: 100px;
  font-family: inherit;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  background: linear-gradient(135deg, var(--silver), var(--slate-light));
  color: var(--base-deep);
  border: none;
  cursor: pointer;
  text-decoration: none;
  transition: transform 0.8s var(--silk-ease), box-shadow 0.8s var(--silk-ease);
}

.nav-cta:hover {
  transform: scale(1.03);
  box-shadow: 0 6px 30px rgba(176,184,196,0.15);
}

.nav-toggle {
  display: none;
  background: none;
  border: none;
  cursor: pointer;
  width: 32px;
  height: 24px;
  position: relative;
  padding: 0;
}

.toggle-bar {
  display: block;
  width: 100%;
  height: 1.5px;
  background: var(--ivory);
  position: absolute;
  left: 0;
  background:white;
  transition: transform 0.6s var(--silk-ease), top 0.6s var(--silk-ease);
}

.toggle-bar:nth-child(1) { top: 6px; }
.toggle-bar:nth-child(2) { top: 16px; }

.nav-toggle.active .toggle-bar:nth-child(1) {
  top: 11px;
  transform: rotate(45deg);
}

.nav-toggle.active .toggle-bar:nth-child(2) {
  top: 11px;
  transform: rotate(-45deg);
}

.mobile-menu {
  position: fixed; inset: 0; z-index: 550;
  pointer-events: none;
  opacity: 0;
  visibility: hidden;
  transition: opacity 0.6s var(--silk-ease), visibility 0.6s var(--silk-ease);
}

.mobile-menu.open {
  opacity: 1;
  visibility: visible;
  pointer-events: auto;
}

.mobile-menu-inner {
  position: absolute; inset: 0;
  background: rgba(15, 17, 21, 0.94);
  backdrop-filter: blur(40px);
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 100px 40px 60px;
  overflow-y: auto;
}

.mobile-menu-link {
 
  display: flex;
  align-items: baseline;
  gap: 16px;
  font-size: clamp(1.6rem, 5vw, 2.6rem);
  font-weight: 300;
  letter-spacing: -0.02em;
   color:white !important;
  text-decoration: none;
  padding: 14px 0;
  border-bottom: 1px solid rgba(156,163,175,0.06);
  opacity: 0;
  transform: translateY(20px);
  transition: opacity 0.3s ease, transform 0.3s ease;
}

.mobile-menu.open .mobile-menu-link {
  opacity: 1;
  transform: translateY(0);
}

body.menu-open {
  overflow: hidden;
}

body.menu-open .top-nav {
  background: rgba(15,17,21,0.95);
  backdrop-filter: blur(20px);
}

@media (max-width: 1024px) {
  .nav-links { display: none; }
  .nav-cta { display: none; }
  .nav-toggle { display: block; }
}

.brand-text {
  font-size: 1.2rem;
  display: inline-block;
  transform: translateY(5px); /* هنا حركة Y */
  transition: transform 0.4s ease;
}
</style>