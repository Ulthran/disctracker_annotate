<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'

const docIframeRef = ref<HTMLIFrameElement | null>(null)
const youtubeIframeRef = ref<HTMLIFrameElement | null>(null)
let player: YT.Player | null = null

const GOOGLE_DOC_URL =
  'https://docs.google.com/document/d/e/2PACX-1vS3SXIULICwhf66A1VpzwuNFuIBqmoeZaZX6mE6xPD58Ll35H5TADaBrZEcD3xKq3TSe0sjjXNMTvFy/pub?embedded=true'
const YOUTUBE_VIDEO_ID = 'dQw4w9WgXcQ'

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

function focusIframe(iframeRef: typeof docIframeRef) {
  const iframe = iframeRef.value
  if (!iframe) return

  iframe.focus()
  try {
    iframe.contentWindow?.focus()
  } catch (error) {
    // Accessing contentWindow focus may fail for cross-origin iframes; ignore.
  }
}

function handleKeydown(event: KeyboardEvent) {
  if (event.altKey && event.key === '1') {
    event.preventDefault()
    focusIframe(docIframeRef)
  } else if (event.altKey && event.key === '2') {
    event.preventDefault()
    focusIframe(youtubeIframeRef)
  }
}

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
})
</script>

<template>
  <main class="workspace">
    <section class="panel panel--doc">
      <header class="panel__header">
        <div>
          <h1>Research Notes</h1>
          <p>Use <kbd>Alt</kbd> + <kbd>1</kbd> to move focus to the document.</p>
        </div>
      </header>
      <iframe
        ref="docIframeRef"
        class="panel__content"
        :src="GOOGLE_DOC_URL"
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
            copy the current timestamp (in milliseconds) to your clipboard.
          </p>
        </div>
      </header>
      <iframe
        ref="youtubeIframeRef"
        class="panel__content"
        :src="`https://www.youtube.com/embed/${YOUTUBE_VIDEO_ID}?enablejsapi=1&rel=0`"
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
