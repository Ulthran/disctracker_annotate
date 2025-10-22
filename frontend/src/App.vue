<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

const MIN_DOC_FLEX = 0.2
const MAX_DOC_FLEX = 0.8

const SIDEBAR_ID = 'workspace-sidebar'

const docIframeRef = ref<HTMLIFrameElement | null>(null)
const youtubeIframeRef = ref<HTMLIFrameElement | null>(null)
const contentRef = ref<HTMLElement | null>(null)
let player: YT.Player | null = null

type YouTubeLinkInfo = {
  videoId: string
  startSeconds: number
}

const DEFAULT_DOC_URL =
  'https://docs.google.com/document/d/1-RxEnSPYk5Nt6QIzDxjhDam1ktuj9t8HTTmTtGm_v3k/edit?tab=t.0'
const DEFAULT_VIDEO_URL =
  'https://www.youtube.com/watch?v=QQlyrXdStK0&t=831s&pp=ygUQdWx0aW1hdGUgZnJpc2JlZQ%3D%3D'

const docUrl = ref(toEmbeddedDocUrl(DEFAULT_DOC_URL))
const docUrlInput = ref(DEFAULT_DOC_URL)
const currentDocSourceUrl = computed(() => docUrlInput.value || DEFAULT_DOC_URL)

const currentVideoId = ref('QQlyrXdStK0')
const currentVideoStartSeconds = ref(831)
const videoUrlInput = ref(DEFAULT_VIDEO_URL)
const playerReady = ref(false)
const docFlex = ref(0.58)
const isDragging = ref(false)
const isSidebarCollapsed = ref(false)
const isSidebarExpanded = computed(() => !isSidebarCollapsed.value)

let activeResizePointerId: number | null = null

function loadYouTubeAPI() {
  return new Promise<void>((resolve) => {
    const existingYT = (window as any).YT
    if (existingYT && typeof existingYT.Player === 'function') {
      resolve()
      return
    }

    const tag = document.createElement('script')
    tag.src = 'https://www.youtube.com/iframe_api'
    document.body.appendChild(tag)

    ;(window as any).onYouTubeIframeAPIReady = () => {
      resolve()
    }
  })
}

function initYouTubePlayer() {
  if (!youtubeIframeRef.value) return

  player = new YT.Player(youtubeIframeRef.value, {
    events: {
      onReady: () => {
        playerReady.value = true
        cueOrLoadVideo(false)
      },
      onStateChange: (event: YT.OnStateChangeEvent) => {
        if (event.data === YT.PlayerState.PAUSED) {
          copyTimestampToClipboard()
        }
      }
    }
  })
}

async function copyTimestampToClipboard() {
  if (!player) return

  const seconds = player.getCurrentTime()
  const milliseconds = Math.round(seconds * 1000)
  const text = milliseconds.toString()

  if (!navigator.clipboard || typeof navigator.clipboard.writeText !== 'function') {
    console.warn('Clipboard API is not available in this browser.')
    return
  }

  try {
    await navigator.clipboard.writeText(text)
    console.log('Copied timestamp to clipboard:', text)
  } catch (error) {
    console.warn('Failed to copy timestamp to clipboard.', error)
  }
}

function focusArea(target: 'doc' | 'video') {
  if (target === 'doc') {
    const iframe = docIframeRef.value
    if (!iframe) return

    iframe.focus()
    try {
      iframe.contentWindow?.focus()
    } catch (error) {
      // Accessing contentWindow focus may fail for cross-origin iframes; ignore.
    }
    return
  }

  const iframe = player?.getIframe() ?? youtubeIframeRef.value
  iframe?.focus()
}

function handleKeydown(event: KeyboardEvent) {
  if (event.altKey && event.key === '1') {
    event.preventDefault()
    focusArea('doc')
  } else if (event.altKey && event.key === '2') {
    event.preventDefault()
    focusArea('video')
  }
}

function parseYouTubeTime(value: string | null): number {
  if (!value) return 0

  const numeric = Number(value)
  if (!Number.isNaN(numeric)) {
    return numeric
  }

  const match = value.match(/(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/i)
  if (!match) return 0

  const [, hours, minutes, seconds] = match
  const totalSeconds =
    (hours ? Number(hours) * 3600 : 0) +
    (minutes ? Number(minutes) * 60 : 0) +
    (seconds ? Number(seconds) : 0)

  return Number.isFinite(totalSeconds) ? totalSeconds : 0
}

function parseYouTubeLink(value: string): YouTubeLinkInfo | null {
  try {
    const url = new URL(value)
    let videoId = ''

    if (url.hostname.includes('youtu.be')) {
      videoId = url.pathname.replace('/', '')
    } else if (url.searchParams.get('v')) {
      videoId = url.searchParams.get('v') ?? ''
    } else {
      const segments = url.pathname.split('/')
      const embedIndex = segments.findIndex((segment) => segment === 'embed')
      if (embedIndex !== -1 && segments[embedIndex + 1]) {
        videoId = segments[embedIndex + 1]
      }
    }

    videoId = videoId.replace(/[^\w-]/g, '')

    if (!videoId) {
      return null
    }

    const startParam = url.searchParams.get('t') ?? url.searchParams.get('start')
    const startSeconds = parseYouTubeTime(startParam)

    return { videoId, startSeconds }
  } catch (error) {
    return null
  }
}

function cueOrLoadVideo(autoplay: boolean) {
  if (!player) return

  const options = {
    videoId: currentVideoId.value,
    startSeconds: currentVideoStartSeconds.value || 0
  }

  if (autoplay) {
    player.loadVideoById(options)
  } else {
    player.cueVideoById(options)
  }
}

function submitDocUrl() {
  const next = docUrlInput.value.trim()
  const chosen = next || DEFAULT_DOC_URL
  docUrl.value = toEmbeddedDocUrl(chosen)
  docUrlInput.value = chosen
}

function submitVideoUrl() {
  const trimmed = videoUrlInput.value.trim()
  if (!trimmed) {
    videoUrlInput.value = DEFAULT_VIDEO_URL
    const fallback = parseYouTubeLink(DEFAULT_VIDEO_URL)
    if (fallback) {
      currentVideoId.value = fallback.videoId
      currentVideoStartSeconds.value = fallback.startSeconds
      if (playerReady.value) {
        cueOrLoadVideo(true)
      }
    }
    return
  }

  const parsed = parseYouTubeLink(trimmed)

  if (!parsed) {
    console.warn('Unable to load video from URL:', trimmed)
    videoUrlInput.value = `https://www.youtube.com/watch?v=${currentVideoId.value}`
    return
  }

  currentVideoId.value = parsed.videoId
  currentVideoStartSeconds.value = parsed.startSeconds
  videoUrlInput.value = trimmed

  if (playerReady.value) {
    cueOrLoadVideo(true)
  }
}

const videoEmbedSrc = computed(() => {
  const params = new URLSearchParams({ enablejsapi: '1', rel: '0' })
  if (currentVideoStartSeconds.value) {
    params.set('start', String(Math.floor(currentVideoStartSeconds.value)))
  }
  return `https://www.youtube.com/embed/${currentVideoId.value}?${params.toString()}`
})

const videoFlex = computed(() => 1 - docFlex.value)

onMounted(async () => {
  await loadYouTubeAPI()
  initYouTubePlayer()
  window.addEventListener('keydown', handleKeydown)
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleKeydown)
  finishResize()
  if (player) {
    player.destroy()
    player = null
  }
  playerReady.value = false
})

function clampDocFlex(value: number) {
  return Math.min(Math.max(value, MIN_DOC_FLEX), MAX_DOC_FLEX)
}

function updateDocFlexFromPointer(event: PointerEvent) {
  if (!contentRef.value) return
  const rect = contentRef.value.getBoundingClientRect()
  if (!rect.height) return
  const ratio = (event.clientY - rect.top) / rect.height
  docFlex.value = clampDocFlex(ratio)
}

function startResize(event: PointerEvent) {
  if (isDragging.value) {
    event.preventDefault()
    return
  }
  event.preventDefault()
  isDragging.value = true
  activeResizePointerId = event.pointerId
  updateDocFlexFromPointer(event)
  window.addEventListener('pointermove', handlePointerMove)
  window.addEventListener('pointerup', stopResize)
  window.addEventListener('pointercancel', stopResize)
}

function handlePointerMove(event: PointerEvent) {
  if (!isDragging.value || event.pointerId !== activeResizePointerId) return
  updateDocFlexFromPointer(event)
}

function stopResize(event: PointerEvent) {
  if (event.pointerId !== activeResizePointerId) return
  finishResize()
}

function removeResizeListeners() {
  window.removeEventListener('pointermove', handlePointerMove)
  window.removeEventListener('pointerup', stopResize)
  window.removeEventListener('pointercancel', stopResize)
}

function finishResize() {
  if (isDragging.value) {
    isDragging.value = false
    activeResizePointerId = null
  }
  removeResizeListeners()
}

function adjustDocFlex(delta: number) {
  docFlex.value = clampDocFlex(docFlex.value + delta)
}

function handleSeparatorKeydown(event: KeyboardEvent) {
  if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
    event.preventDefault()
    adjustDocFlex(0.03)
  } else if (event.key === 'ArrowDown' || event.key === 'ArrowRight') {
    event.preventDefault()
    adjustDocFlex(-0.03)
  } else if (event.key === 'Home') {
    event.preventDefault()
    docFlex.value = MAX_DOC_FLEX
  } else if (event.key === 'End') {
    event.preventDefault()
    docFlex.value = MIN_DOC_FLEX
  }
}

function toggleSidebar() {
  isSidebarCollapsed.value = !isSidebarCollapsed.value
}

function toEmbeddedDocUrl(raw: string) {
  try {
    const url = new URL(raw)
    const docMatch = url.pathname.match(/\/document(?:\/u\/\d+)?\/d\/([\w-]+)/)
    if (docMatch) {
      const docId = docMatch[1]
      const hash = url.hash ?? ''
      const embedUrl = new URL(`https://docs.google.com/document/d/${docId}/preview`)
      url.searchParams.forEach((value, key) => {
        if (key !== 'rm') {
          embedUrl.searchParams.set(key, value)
        }
      })
      embedUrl.searchParams.set('rm', 'minimal')
      return `${embedUrl.toString()}${hash}`
    }
    return raw
  } catch (error) {
    return raw
  }
}
</script>

<template>
  <main class="workspace">
    <button
      v-if="isSidebarCollapsed"
      class="sidebar-toggle"
      type="button"
      :aria-controls="SIDEBAR_ID"
      :aria-expanded="isSidebarExpanded"
      @click="toggleSidebar"
    >
      Show sidebar
    </button>

    <aside
      v-show="!isSidebarCollapsed"
      :id="SIDEBAR_ID"
      class="sidebar"
      :aria-hidden="isSidebarCollapsed"
    >
      <section class="sidebar__group">
        <div class="sidebar__group-header">
          <h1 class="sidebar__title">Research Notes</h1>
          <button
            class="sidebar__collapse-button"
            type="button"
            :aria-controls="SIDEBAR_ID"
            :aria-expanded="isSidebarExpanded"
            @click="toggleSidebar"
          >
            Hide sidebar
          </button>
        </div>
        <p class="sidebar__text">
          Use <kbd>Alt</kbd> + <kbd>1</kbd> to focus the document. Paste a Google Doc link and press
          <kbd>Enter</kbd> to refresh the embed.
        </p>
        <p class="sidebar__note">
          Google Docs only allows read-only previews inside the workspace—Google blocks editing views
          from loading in embedded frames, so use the link below to edit in a new tab if you need to
          make changes.
        </p>
        <form class="sidebar__form" @submit.prevent="submitDocUrl">
          <label class="sr-only" for="doc-url-input">Google Doc URL</label>
          <input
            id="doc-url-input"
            v-model="docUrlInput"
            class="sidebar__input"
            type="url"
            placeholder="https://docs.google.com/..."
            inputmode="url"
            spellcheck="false"
          />
          <button class="sidebar__button" type="submit">Load document</button>
        </form>
        <a
          class="sidebar__link"
          :href="currentDocSourceUrl"
          target="_blank"
          rel="noopener noreferrer"
        >
          Open in Google Docs
        </a>
      </section>

      <section class="sidebar__group">
        <h2 class="sidebar__title">Reference Video</h2>
        <p class="sidebar__text">
          Use <kbd>Alt</kbd> + <kbd>2</kbd> to focus the player. Pause with <kbd>k</kbd> or <kbd>space</kbd> to copy
          the current timestamp.
        </p>
        <form class="sidebar__form" @submit.prevent="submitVideoUrl">
          <label class="sr-only" for="video-url-input">YouTube URL</label>
          <input
            id="video-url-input"
            v-model="videoUrlInput"
            class="sidebar__input"
            type="url"
            placeholder="https://youtube.com/watch?v=..."
            inputmode="url"
            spellcheck="false"
          />
          <button class="sidebar__button" type="submit">Load video</button>
        </form>
      </section>
    </aside>

    <section ref="contentRef" class="content">
      <div
        class="embed embed--doc"
        :style="{ flexGrow: docFlex, flexBasis: '0%' }"
      >
        <span class="embed__label">Document</span>
        <iframe
          ref="docIframeRef"
          class="embed__frame"
          :src="docUrl"
          title="Project Google Document"
          frameborder="0"
          tabindex="0"
        ></iframe>
      </div>

      <div
        class="split-handle"
        role="separator"
        aria-orientation="horizontal"
        :aria-valuenow="Math.round(docFlex * 100)"
        :aria-valuemin="Math.round(MIN_DOC_FLEX * 100)"
        :aria-valuemax="Math.round(MAX_DOC_FLEX * 100)"
        tabindex="0"
        @pointerdown="startResize"
        @keydown="handleSeparatorKeydown"
        :class="{ 'split-handle--dragging': isDragging }"
      ></div>

      <div
        class="embed embed--video"
        :style="{ flexGrow: videoFlex, flexBasis: '0%' }"
      >
        <span class="embed__label">Video</span>
        <iframe
          ref="youtubeIframeRef"
          class="embed__frame"
          :src="videoEmbedSrc"
          title="YouTube video player"
          frameborder="0"
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          allowfullscreen
          tabindex="0"
        ></iframe>
      </div>
    </section>
  </main>
</template>

<style scoped>
.workspace {
  display: flex;
  height: 100vh;
  background: linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
  color: #0f172a;
  position: relative;
}

.sidebar {
  flex: 0 0 clamp(15rem, 20vw, 21rem);
  display: flex;
  flex-direction: column;
  gap: 1rem;
  padding: 1rem 1.25rem;
  box-sizing: border-box;
  background: rgba(255, 255, 255, 0.65);
  backdrop-filter: blur(10px);
  border-right: 1px solid rgba(15, 23, 42, 0.08);
  overflow-y: auto;
}

.sidebar-toggle {
  position: absolute;
  top: 1rem;
  left: 1rem;
  z-index: 10;
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.55rem 0.95rem;
  border-radius: 999px;
  border: none;
  background: linear-gradient(135deg, #2563eb, #1d4ed8);
  color: #f8fafc;
  font-size: 0.9rem;
  font-weight: 600;
  letter-spacing: 0.01em;
  cursor: pointer;
  box-shadow: 0 12px 24px rgba(37, 99, 235, 0.25);
  transition: transform 0.2s ease, box-shadow 0.2s ease, background 0.2s ease;
}

.sidebar-toggle:hover,
.sidebar-toggle:focus-visible {
  background: linear-gradient(135deg, #1e40af, #1d4ed8);
  transform: translateY(-1px);
  box-shadow: 0 14px 32px rgba(30, 64, 175, 0.35);
}

.sidebar-toggle:focus-visible {
  outline: 3px solid rgba(129, 140, 248, 0.7);
  outline-offset: 2px;
}

.sidebar__group {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.sidebar__group-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  flex-wrap: wrap;
}

.sidebar__collapse-button {
  margin-left: auto;
  padding: 0.4rem 0.7rem;
  border-radius: 0.6rem;
  border: 1px solid rgba(37, 99, 235, 0.35);
  background: rgba(37, 99, 235, 0.08);
  color: #1d4ed8;
  font-weight: 600;
  font-size: 0.85rem;
  letter-spacing: 0.01em;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  transition: background 0.2s ease, color 0.2s ease, box-shadow 0.2s ease, transform 0.2s ease;
}

.sidebar__collapse-button:hover {
  background: rgba(37, 99, 235, 0.16);
  color: #1e3a8a;
  box-shadow: 0 6px 16px rgba(37, 99, 235, 0.18);
  transform: translateY(-1px);
}

.sidebar__collapse-button:focus-visible {
  outline: 3px solid rgba(37, 99, 235, 0.45);
  outline-offset: 2px;
}

.sidebar__title {
  margin: 0;
  font-size: 1.05rem;
  font-weight: 600;
}

.sidebar__text {
  margin: 0;
  color: #475569;
  font-size: 0.9rem;
  line-height: 1.4;
}

.sidebar__note {
  margin: 0;
  color: #64748b;
  font-size: 0.8rem;
  line-height: 1.4;
}

.sidebar__form {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.sidebar__input {
  width: 100%;
  padding: 0.55rem 0.75rem;
  border-radius: 0.55rem;
  border: 1px solid rgba(15, 23, 42, 0.18);
  font-size: 0.9rem;
  font-family: 'Inter', 'Segoe UI', system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}

.sidebar__input:focus {
  outline: none;
  border-color: rgba(37, 99, 235, 0.55);
  box-shadow: 0 0 0 2px rgba(37, 99, 235, 0.25);
}

.sidebar__button {
  padding: 0.5rem 0.85rem;
  border-radius: 0.55rem;
  border: none;
  background: linear-gradient(135deg, #2563eb, #1d4ed8);
  color: #ffffff;
  font-weight: 600;
  font-size: 0.9rem;
  cursor: pointer;
  transition: transform 0.15s ease, box-shadow 0.15s ease;
  align-self: flex-start;
}

.sidebar__button:hover {
  transform: translateY(-1px);
  box-shadow: 0 8px 16px rgba(37, 99, 235, 0.25);
}

.sidebar__button:focus {
  outline: none;
  box-shadow: 0 0 0 2px rgba(37, 99, 235, 0.35);
}

.sidebar__link {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.85rem;
  font-weight: 600;
  color: #1d4ed8;
  text-decoration: none;
  transition: color 0.2s ease, transform 0.2s ease;
}

.sidebar__link:hover {
  color: #1e3a8a;
  transform: translateY(-1px);
}

.sidebar__link:focus-visible {
  outline: 3px solid rgba(37, 99, 235, 0.35);
  outline-offset: 2px;
  border-radius: 0.35rem;
}

.content {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  padding: 0.75rem 0.9rem 0.9rem;
  box-sizing: border-box;
  min-width: 0;
  min-height: 0;
}

.embed {
  position: relative;
  flex: 1;
  min-height: 0;
  border-radius: 0.75rem;
  background-color: #ffffff;
  box-shadow: 0 10px 26px rgba(15, 23, 42, 0.12);
  overflow: hidden;
}

.embed__label {
  position: absolute;
  top: 0.75rem;
  left: 0.75rem;
  z-index: 1;
  padding: 0.15rem 0.6rem;
  border-radius: 999px;
  background: rgba(15, 23, 42, 0.72);
  color: #f8fafc;
  font-size: 0.75rem;
  letter-spacing: 0.02em;
  text-transform: uppercase;
}

.embed__frame {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  border: none;
}

.embed__frame:focus-visible {
  outline: 3px solid rgba(37, 99, 235, 0.6);
  outline-offset: 0;
}

.split-handle {
  position: relative;
  flex: 0 0 auto;
  height: 0.85rem;
  cursor: row-resize;
  display: flex;
  align-items: center;
  justify-content: center;
  touch-action: none;
  border-radius: 0.5rem;
}

.split-handle::before {
  content: '';
  width: 60%;
  max-width: 12rem;
  height: 3px;
  border-radius: 999px;
  background: rgba(15, 23, 42, 0.28);
  transition: background 0.2s ease, transform 0.2s ease;
}

.split-handle:hover::before,
.split-handle:focus-visible::before,
.split-handle--dragging::before {
  background: rgba(37, 99, 235, 0.75);
  transform: scaleX(1.05);
}

@media (max-width: 960px) {
  .workspace {
    flex-direction: column;
  }

  .sidebar {
    flex: none;
    width: auto;
    border-right: none;
    border-bottom: 1px solid rgba(15, 23, 42, 0.08);
    flex-direction: column;
    padding: 0.75rem 1rem;
  }

  .sidebar-toggle {
    top: 0.75rem;
    left: 0.75rem;
    padding: 0.5rem 0.85rem;
  }

  .sidebar__group-header {
    gap: 0.5rem;
  }

  .sidebar__collapse-button {
    width: 100%;
    margin-left: 0;
    justify-content: center;
  }

  .content {
    padding: 0.75rem;
  }
}

.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}

kbd {
  display: inline-block;
  padding: 0.1rem 0.4rem;
  margin: 0 0.1rem;
  border-radius: 0.4rem;
  background: #e2e8f0;
  border: 1px solid #cbd5f5;
  font-size: 0.85rem;
  font-family: 'JetBrains Mono', 'Fira Code', 'Menlo', monospace;
  box-shadow: inset 0 -2px 0 rgba(15, 23, 42, 0.15);
}
</style>
