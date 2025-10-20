<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'

type GoogleCredentialResponse = {
  credential: string
  clientId: string
  select_by: string
}

type GoogleIdInitializeOptions = {
  client_id: string
  callback: (response: GoogleCredentialResponse) => void
  auto_select?: boolean
  cancel_on_tap_out?: boolean
  prompt_parent_id?: string
}

type GoogleIdRenderButtonOptions = {
  type?: 'standard' | 'icon'
  theme?: 'outline' | 'filled_blue' | 'filled_black'
  size?: 'large' | 'medium' | 'small'
  shape?: 'rectangular' | 'pill' | 'circle' | 'square'
  text?: 'signin_with' | 'signup_with' | 'continue_with' | 'signin'
  logo_alignment?: 'left' | 'center'
  width?: string | number
}

type GoogleIdentity = {
  accounts?: {
    id?: {
      initialize: (options: GoogleIdInitializeOptions) => void
      renderButton: (parent: HTMLElement, options: GoogleIdRenderButtonOptions) => void
      prompt: () => void
      disableAutoSelect: () => void
      revoke?: (hint: string, callback: () => void) => void
    }
  }
}

declare global {
  interface Window {
    google?: GoogleIdentity
  }
}

type UserProfile = {
  name: string
  email: string
  picture?: string
}

const MIN_DOC_FLEX = 0.2
const MAX_DOC_FLEX = 0.8

const googleClientId = import.meta.env.VITE_GOOGLE_CLIENT_ID ?? ''
const googleAuthReady = ref(false)
const authError = ref<string | null>(null)
const googleButtonContainerRef = ref<HTMLElement | null>(null)
const userProfile = ref<UserProfile | null>(null)
const youTubeApiReady = ref(false)

const docIframeRef = ref<HTMLIFrameElement | null>(null)
const youtubeIframeRef = ref<HTMLIFrameElement | null>(null)
const contentRef = ref<HTMLElement | null>(null)
let player: YT.Player | null = null

const isAuthenticated = computed(() => !!userProfile.value)

const userInitials = computed(() => {
  const name = userProfile.value?.name?.trim()
  if (name) {
    return name
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part.charAt(0).toUpperCase())
      .join('')
  }

  const email = userProfile.value?.email ?? ''
  return email ? email.charAt(0).toUpperCase() : '?'
})

let googleScriptPromise: Promise<void> | null = null

function getGoogleAccountsId() {
  return window.google?.accounts?.id ?? null
}

function loadGoogleIdentityScript() {
  if (googleScriptPromise) {
    return googleScriptPromise
  }

  googleScriptPromise = new Promise<void>((resolve, reject) => {
    if (getGoogleAccountsId()) {
      resolve()
      return
    }

    const script = document.createElement('script')
    script.src = 'https://accounts.google.com/gsi/client'
    script.async = true
    script.defer = true
    script.onload = () => resolve()
    script.onerror = () => reject(new Error('Failed to load Google Identity Services script.'))
    document.head.appendChild(script)
  })

  return googleScriptPromise
}

function renderGoogleButton() {
  const googleId = getGoogleAccountsId()
  if (!googleId || !googleButtonContainerRef.value) {
    return
  }

  googleButtonContainerRef.value.innerHTML = ''
  googleId.renderButton(googleButtonContainerRef.value, {
    type: 'standard',
    theme: 'filled_blue',
    size: 'large',
    shape: 'pill',
    text: 'signin_with'
  })
}

function decodeGoogleCredential(credential: string): UserProfile | null {
  try {
    const payloadSegment = credential.split('.')[1]
    if (!payloadSegment) {
      return null
    }

    const normalized = payloadSegment.replace(/-/g, '+').replace(/_/g, '/')
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
    const json = atob(padded)
    const payload = JSON.parse(json) as {
      name?: string
      email?: string
      picture?: string
    }

    if (!payload.email) {
      return null
    }

    return {
      name: payload.name ?? payload.email,
      email: payload.email,
      picture: payload.picture
    }
  } catch (error) {
    console.warn('Failed to decode Google credential.', error)
    return null
  }
}

function handleCredentialResponse(response: GoogleCredentialResponse) {
  const profile = decodeGoogleCredential(response.credential)
  if (!profile) {
    authError.value = 'Unable to read Google profile information.'
    return
  }

  authError.value = null
  userProfile.value = profile
}

async function initializeGoogleAuth() {
  if (!googleClientId) {
    authError.value = 'Missing Google client ID configuration.'
    return
  }

  try {
    await loadGoogleIdentityScript()
  } catch (error) {
    console.error(error)
    authError.value = 'Unable to load Google authentication services.'
    return
  }

  const googleId = getGoogleAccountsId()
  if (!googleId) {
    authError.value = 'Google authentication is unavailable in this browser.'
    return
  }

  googleId.initialize({
    client_id: googleClientId,
    callback: handleCredentialResponse,
    auto_select: false,
    cancel_on_tap_out: true
  })

  googleAuthReady.value = true
  googleId.prompt()
}

function finalizeSignOut() {
  userProfile.value = null
  if (player) {
    player.destroy()
    player = null
  }
  playerReady.value = false
}

function signOut() {
  const googleId = getGoogleAccountsId()

  const completeSignOut = () => {
    finalizeSignOut()
    void nextTick(() => {
      if (googleAuthReady.value && !isAuthenticated.value) {
        renderGoogleButton()
        googleId?.prompt()
      }
    })
  }

  if (googleId) {
    googleId.disableAutoSelect()
    const email = userProfile.value?.email
    if (email && typeof googleId.revoke === 'function') {
      googleId.revoke(email, completeSignOut)
      return
    }
  }

  completeSignOut()
}

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

const currentVideoId = ref('QQlyrXdStK0')
const currentVideoStartSeconds = ref(831)
const videoUrlInput = ref(DEFAULT_VIDEO_URL)
const playerReady = ref(false)
const docFlex = ref(0.58)
const isDragging = ref(false)

let activeResizePointerId: number | null = null

watch(
  [googleAuthReady, isAuthenticated],
  async ([ready, authed]) => {
    if (ready && !authed) {
      await nextTick()
      renderGoogleButton()
    }
  },
  { immediate: true }
)

watch(isAuthenticated, (authed) => {
  if (!authed && player) {
    player.destroy()
    player = null
    playerReady.value = false
  }
})

watch(
  [() => youtubeIframeRef.value, youTubeApiReady, isAuthenticated],
  async ([iframe, apiReady, authed]) => {
    if (iframe && apiReady && authed) {
      await nextTick()
      initYouTubePlayer()
    }
  }
)

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
  if (player || !youtubeIframeRef.value) return

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
  if (!isAuthenticated.value) return

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
  if (!isAuthenticated.value) return

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
  void initializeGoogleAuth()
  await loadYouTubeAPI()
  youTubeApiReady.value = true
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
  <main v-if="isAuthenticated" class="workspace">
    <aside class="sidebar">
      <header class="sidebar__header">
        <div class="user-pill">
          <div
            class="user-pill__avatar"
            :class="{ 'user-pill__avatar--fallback': !userProfile?.picture }"
            aria-hidden="true"
          >
            <img v-if="userProfile?.picture" :src="userProfile.picture" alt="" />
            <span v-else>{{ userInitials }}</span>
          </div>
          <div class="user-pill__meta">
            <span class="user-pill__name">{{ userProfile?.name }}</span>
            <span class="user-pill__email">{{ userProfile?.email }}</span>
          </div>
        </div>
        <button class="sidebar__signout" type="button" @click="signOut">Sign out</button>
      </header>

      <section class="sidebar__group">
        <h1 class="sidebar__title">Research Notes</h1>
        <p class="sidebar__text">
          Use <kbd>Alt</kbd> + <kbd>1</kbd> to focus the document. Paste a Google Doc link and press
          <kbd>Enter</kbd> to refresh the embed.
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

  <div v-else class="auth">
    <div class="auth__panel">
      <h1 class="auth__title">Sign in to continue</h1>
      <p class="auth__text">
        Sign in with Google to open the shared document and video with your account permissions.
      </p>
      <div class="auth__button-area">
        <div
          ref="googleButtonContainerRef"
          class="auth__button-slot"
          v-show="googleAuthReady"
        ></div>
        <p v-if="!googleAuthReady && !authError" class="auth__hint">Loading Google Sign-In…</p>
        <p v-if="authError" class="auth__error">{{ authError }}</p>
      </div>
      <p class="auth__disclaimer">
        Your Google credential is kept in this session only and used to authenticate the embeds.
      </p>
    </div>
  </div>
</template>

<style scoped>
.workspace {
  display: flex;
  height: 100vh;
  background: linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
  color: #0f172a;
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

.sidebar__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.85rem;
  padding-bottom: 1rem;
  margin-bottom: 1rem;
  border-bottom: 1px solid rgba(15, 23, 42, 0.08);
}

.user-pill {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  min-width: 0;
}

.user-pill__avatar {
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 50%;
  background: #2563eb;
  color: #f8fafc;
  font-weight: 600;
  font-size: 0.95rem;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
  box-shadow: 0 6px 20px rgba(37, 99, 235, 0.3);
}

.user-pill__avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.user-pill__avatar--fallback {
  background: linear-gradient(135deg, #2563eb, #1e293b);
  box-shadow: 0 6px 22px rgba(30, 64, 175, 0.35);
}

.user-pill__meta {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.user-pill__name {
  font-size: 0.98rem;
  font-weight: 600;
  color: #0f172a;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.user-pill__email {
  font-size: 0.8rem;
  color: rgba(15, 23, 42, 0.7);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.sidebar__signout {
  border: none;
  border-radius: 999px;
  background: #1d4ed8;
  color: #f8fafc;
  font-weight: 600;
  font-size: 0.85rem;
  padding: 0.42rem 0.95rem;
  cursor: pointer;
  box-shadow: 0 8px 20px rgba(37, 99, 235, 0.28);
  transition: background 0.2s ease, box-shadow 0.2s ease;
}

.sidebar__signout:hover {
  background: #1e40af;
  box-shadow: 0 10px 24px rgba(30, 64, 175, 0.35);
}

.sidebar__signout:focus {
  outline: none;
  box-shadow: 0 0 0 2px rgba(37, 99, 235, 0.35);
}

.sidebar__group {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
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

  .sidebar__header {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.75rem;
    padding-bottom: 0.85rem;
    margin-bottom: 0.85rem;
  }

  .sidebar__signout {
    align-self: stretch;
    justify-content: center;
  }

  .content {
    padding: 0.75rem;
  }
}

.auth {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 2.5rem;
  background: linear-gradient(180deg, #e0f2fe 0%, #e2e8f0 100%);
  box-sizing: border-box;
}

.auth__panel {
  max-width: 420px;
  width: 100%;
  padding: 2.5rem 2.75rem;
  border-radius: 1.15rem;
  background: rgba(255, 255, 255, 0.92);
  box-shadow: 0 28px 60px rgba(15, 23, 42, 0.18);
  text-align: center;
  backdrop-filter: blur(6px);
}

.auth__title {
  margin: 0 0 0.85rem;
  font-size: 1.75rem;
  font-weight: 700;
  color: #0f172a;
}

.auth__text {
  margin: 0 0 1.6rem;
  color: rgba(15, 23, 42, 0.78);
  line-height: 1.6;
}

.auth__button-area {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 1.5rem;
  min-height: 3.25rem;
}

.auth__button-slot {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 3rem;
}

.auth__hint {
  margin: 0;
  font-size: 0.9rem;
  color: rgba(15, 23, 42, 0.6);
}

.auth__error {
  margin: 0;
  color: #dc2626;
  font-weight: 600;
}

.auth__disclaimer {
  margin: 0;
  font-size: 0.85rem;
  color: rgba(15, 23, 42, 0.65);
  line-height: 1.6;
}

@media (max-width: 640px) {
  .auth {
    padding: 1.5rem;
  }

  .auth__panel {
    padding: 2rem 1.5rem;
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
