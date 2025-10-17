<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

const docIframeRef = ref<HTMLIFrameElement | null>(null)
const youtubeIframeRef = ref<HTMLIFrameElement | null>(null)
let player: YT.Player | null = null

type YouTubeLinkInfo = {
  videoId: string
  startSeconds: number
}

const DEFAULT_DOC_URL =
  'https://docs.google.com/document/d/1-RxEnSPYk5Nt6QIzDxjhDam1ktuj9t8HTTmTtGm_v3k/edit?tab=t.0'
const DEFAULT_VIDEO_URL =
  'https://www.youtube.com/watch?v=QQlyrXdStK0&t=831s&pp=ygUQdWx0aW1hdGUgZnJpc2JlZQ%3D%3D'

const docUrl = ref(DEFAULT_DOC_URL)
const docUrlInput = ref(DEFAULT_DOC_URL)

const currentVideoId = ref('QQlyrXdStK0')
const currentVideoStartSeconds = ref(831)
const videoUrlInput = ref(DEFAULT_VIDEO_URL)
const playerReady = ref(false)

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
  docUrl.value = next || DEFAULT_DOC_URL
  docUrlInput.value = docUrl.value
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

onMounted(async () => {
  await loadYouTubeAPI()
  initYouTubePlayer()
  window.addEventListener('keydown', handleKeydown)
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleKeydown)
  if (player) {
    player.destroy()
    player = null
  }
  playerReady.value = false
})
</script>

<template>
  <main class="workspace">
    <section class="panel panel--doc">
      <header class="panel__header">
        <div>
          <h1>Research Notes</h1>
          <p>
            Use <kbd>Alt</kbd> + <kbd>1</kbd> to move focus to the document. Paste a new link and press
            <kbd>Enter</kbd> to load it below.
          </p>
        </div>
        <form class="panel__form" @submit.prevent="submitDocUrl">
          <label class="sr-only" for="doc-url-input">Google Doc URL</label>
          <input
            id="doc-url-input"
            v-model="docUrlInput"
            class="panel__input"
            type="url"
            placeholder="Paste a Google Doc link"
            inputmode="url"
            spellcheck="false"
          />
          <button class="panel__button" type="submit">Load</button>
        </form>
      </header>
      <iframe
        ref="docIframeRef"
        class="panel__content"
        :src="docUrl"
        title="Project Google Document"
        frameborder="0"
        tabindex="0"
      ></iframe>
    </section>

    <section class="panel panel--video">
      <header class="panel__header">
        <div>
          <h2>Reference Video</h2>
          <p>
            Use <kbd>Alt</kbd> + <kbd>2</kbd> to focus the video. Pause with <kbd>k</kbd> or <kbd>space</kbd> to
            copy the current timestamp (in milliseconds) to your clipboard. Paste any YouTube link and press
            <kbd>Enter</kbd> to load it.
          </p>
        </div>
        <form class="panel__form" @submit.prevent="submitVideoUrl">
          <label class="sr-only" for="video-url-input">YouTube URL</label>
          <input
            id="video-url-input"
            v-model="videoUrlInput"
            class="panel__input"
            type="url"
            placeholder="Paste a YouTube link"
            inputmode="url"
            spellcheck="false"
          />
          <button class="panel__button" type="submit">Load</button>
        </form>
      </header>
      <iframe
        ref="youtubeIframeRef"
        class="panel__content"
        :src="videoEmbedSrc"
        title="YouTube video player"
        frameborder="0"
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
        allowfullscreen
        tabindex="0"
      ></iframe>
    </section>
  </main>
</template>

<style scoped>
.workspace {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
  color: #0f172a;
}

.panel {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
  padding: 1.5rem clamp(1.5rem, 3vw, 2.5rem);
  box-sizing: border-box;
}

.panel--doc {
  border-bottom: 1px solid rgba(15, 23, 42, 0.08);
}

.panel__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 1rem;
  flex-wrap: wrap;
}

.panel__header h1,
.panel__header h2 {
  margin: 0 0 0.25rem;
  font-weight: 600;
}

.panel__header p {
  margin: 0;
  color: #475569;
  font-size: 0.95rem;
}

.panel__content {
  flex: 1;
  border: none;
  border-radius: 0.75rem;
  background-color: #ffffff;
  box-shadow: 0 12px 30px rgba(15, 23, 42, 0.1);
}

.panel__content:focus {
  outline: 3px solid rgba(37, 99, 235, 0.6);
  outline-offset: 0;
}

.panel__form {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  flex-wrap: nowrap;
}

.panel__input {
  flex: 1 1 auto;
  min-width: 18rem;
  padding: 0.6rem 0.8rem;
  border-radius: 0.6rem;
  border: 1px solid rgba(15, 23, 42, 0.15);
  font-size: 0.95rem;
  font-family: 'Inter', 'Segoe UI', system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}

.panel__input:focus {
  outline: none;
  border-color: rgba(37, 99, 235, 0.5);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.2);
}

.panel__button {
  padding: 0.55rem 1.2rem;
  border-radius: 0.6rem;
  border: none;
  background: linear-gradient(135deg, #2563eb, #1d4ed8);
  color: #ffffff;
  font-weight: 600;
  font-size: 0.95rem;
  cursor: pointer;
  transition: transform 0.15s ease, box-shadow 0.15s ease;
}

.panel__button:hover {
  transform: translateY(-1px);
  box-shadow: 0 8px 18px rgba(37, 99, 235, 0.25);
}

.panel__button:focus {
  outline: none;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.35);
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
