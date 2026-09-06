import { nextTick, onMounted, onUnmounted, watch, type Ref } from 'vue'
import gsap from 'gsap'
import { CustomEase } from 'gsap/CustomEase'
import { DrawSVGPlugin } from 'gsap/DrawSVGPlugin'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import { SplitText } from 'gsap/SplitText'
import type { Locale } from '../i18n'

gsap.registerPlugin(ScrollTrigger, SplitText, DrawSVGPlugin, CustomEase)
CustomEase.create('jingyinRise', '0.22,0.61,0.36,1')

export function useLandingMotion(pageEl: Ref<HTMLElement | undefined>, locale: Ref<Locale>) {
  let ctx: gsap.Context | undefined

  function refreshOnImages(root: HTMLElement) {
    for (const img of root.querySelectorAll('img')) {
      if (img.complete) continue
      img.addEventListener('load', () => ScrollTrigger.refresh(), { once: true })
    }
  }

  function setup(root: HTMLElement) {
    ctx?.revert()
    ctx = gsap.context(() => {
      const mm = gsap.matchMedia()

      mm.add('(prefers-reduced-motion: reduce)', () => {
        gsap.set(
          '.hero-copy > *, .hero-media, [data-reveal], .eyebrow-mark line',
          { autoAlpha: 1, y: 0, clearProps: 'transform' },
        )
      })

      mm.add('(prefers-reduced-motion: no-preference)', () => {
        const rise = 'jingyinRise'
        const titleLine = root.querySelector('.hero-title-line')
        const highlight = root.querySelector('.hero-highlight')

        if (titleLine) {
          SplitText.create(titleLine, {
            type: 'words, chars',
            charsClass: 'char',
            aria: 'auto',
            autoSplit: true,
            onSplit(self) {
              gsap.set(self.elements, { autoAlpha: 1 })
              return gsap.fromTo(
                self.chars,
                { autoAlpha: 0, y: 16 },
                { autoAlpha: 1, y: 0, duration: 0.45, stagger: 0.02, ease: rise },
              )
            },
          })
        }

        if (highlight) {
          SplitText.create(highlight, {
            type: 'words, chars',
            charsClass: 'char',
            aria: 'auto',
            autoSplit: true,
            onSplit(self) {
              gsap.set(self.elements, { autoAlpha: 1 })
              return gsap.fromTo(
                self.chars,
                { autoAlpha: 0, y: 14 },
                {
                  autoAlpha: 1,
                  y: 0,
                  duration: 0.42,
                  stagger: 0.018,
                  delay: 0.18,
                  ease: rise,
                },
              )
            },
          })
        }

        const intro = gsap.timeline({ defaults: { ease: rise } })
        intro.fromTo('.hero-eyebrow', { autoAlpha: 0, y: 12 }, { autoAlpha: 1, y: 0, duration: 0.45 }, 0)
        intro.from('.hero-eyebrow .eyebrow-mark line', { drawSVG: 0, duration: 0.55 }, 0.05)
        intro.fromTo('.hero-copy > p', { autoAlpha: 0, y: 14 }, { autoAlpha: 1, y: 0, duration: 0.5 }, 0.32)
        intro.fromTo('.hero-actions', { autoAlpha: 0, y: 12 }, { autoAlpha: 1, y: 0, duration: 0.45 }, 0.42)
        intro.fromTo('.trust li', { autoAlpha: 0, y: 10 }, { autoAlpha: 1, y: 0, duration: 0.4, stagger: 0.06 }, 0.5)
        intro.fromTo('.hero-media', { autoAlpha: 0, y: 28 }, { autoAlpha: 1, y: 0, duration: 0.85 }, 0.08)

        ScrollTrigger.batch('[data-reveal]', {
          start: 'top 88%',
          once: true,
          interval: 0.12,
          onEnter(batch) {
            gsap.fromTo(
              batch,
              { autoAlpha: 0, y: 24 },
              { autoAlpha: 1, y: 0, duration: 0.7, ease: rise, stagger: 0.08, overwrite: true },
            )
            const marks = batch.flatMap((el) =>
              Array.from((el as HTMLElement).querySelectorAll('.eyebrow-mark line')),
            )
            if (marks.length) {
              gsap.from(marks, { drawSVG: 0, duration: 0.5, ease: rise, stagger: 0.06 })
            }
          },
        })

        root.querySelectorAll<HTMLElement>('.steps article').forEach((article) => {
          const device = article.querySelector('.path-device')
          if (!device) return
          gsap.fromTo(
            device,
            { y: 18 },
            {
              y: -10,
              ease: 'none',
              scrollTrigger: {
                trigger: article,
                start: 'top 90%',
                end: 'bottom 25%',
                scrub: 0.7,
              },
            },
          )
        })

        gsap.to('.hero-device-shift', {
          yPercent: 7,
          ease: 'none',
          scrollTrigger: {
            trigger: '.hero',
            start: 'top top',
            end: 'bottom top',
            scrub: 0.65,
          },
        })
      })
    }, root)

    refreshOnImages(root)
  }

  onMounted(() => {
    if (pageEl.value) setup(pageEl.value)
  })

  watch(locale, async () => {
    ctx?.revert()
    ctx = undefined
    await nextTick()
    if (pageEl.value) setup(pageEl.value)
  })

  onUnmounted(() => {
    ctx?.revert()
  })
}
