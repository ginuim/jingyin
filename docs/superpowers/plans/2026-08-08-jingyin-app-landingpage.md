# 镜隐 App Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a standalone Vite+Vue App marketing site in `landingpage/` with 4 locales and per-locale privacy pages.

**Architecture:** Vue 3 + vue-router SPA; locale from path; copy in `src/i18n/locales/*` and privacy in `src/i18n/privacy/*`; tokens from AppPalette; screenshots copied into `public/screenshots/`.

**Tech Stack:** Vue 3, TypeScript, Vite, vue-router, pnpm

---

### Task 1: Scaffold + assets

- [ ] Create Vite Vue-TS project under `landingpage/`
- [ ] Add vue-router; copy app icon + selected sim screenshots
- [ ] Add `tokens.css` + `config.ts`

### Task 2: i18n + router

- [ ] Locale types, detect, storage
- [ ] Four locale copy modules + privacy modules
- [ ] Routes for home/privacy per locale

### Task 3: UI pages

- [ ] Header, Footer, PhoneFrame, Home, Privacy
- [ ] Placeholder App Store CTA

### Task 4: Verify

- [ ] `pnpm build` succeeds
- [ ] Smoke-check routes locally
