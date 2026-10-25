import { createContext, useContext, useState, useRef, useEffect, useCallback, useMemo, type ReactNode } from 'react'
import type { Track, RepeatMode } from '@/types'
import { extractAudio } from '@/services/api'
import { addRecentTrack, loadFavoriteTracks, toggleFavoriteTrack } from '@/utils/storage'
import { useAppSettings } from '@/hooks/useAppSettings'
import { isNativeIOS, NativePlayer, type NativePlaybackState } from '@/platform/native'
import { insertNext, moveTrack, uniqueTracks } from '@/platform/queue'

interface PlayerValue {
  currentTrack: Track | null; queue: Track[]; isPlaying: boolean; loadingAudio: boolean
  volume: number; isMuted: boolean; repeatMode: RepeatMode; isShuffled: boolean
  play: (track: Track) => void; pause: () => void; togglePlay: () => void; next: () => void; prev: () => void
  setVolume: (value: number) => void; setIsMuted: (value: boolean) => void
  setRepeatMode: (value: RepeatMode) => void; setIsShuffled: (value: boolean) => void
  addToQueue: (track: Track) => void; addTracksToQueue: (tracks: Track[]) => void
  removeFromQueue: (id: string) => void; removeMultipleFromQueue: (ids: string[]) => void
  moveInQueue: (from: number, to: number) => void; playNow: (track: Track) => void
  playNext: (track: Track) => void; clearQueue: () => void; toggleLike: (id: string) => void
  playAll: (tracks: Track[]) => void; playFromQueue: (index: number) => void
}
interface Progress { progress: number; duration: number; setProgress: (position: number) => void }
interface Saved {
  currentTrack: Track | null; queue: Track[]; progress: number; volume: number
  isMuted: boolean; repeatMode: RepeatMode; isShuffled: boolean
}
const PlayerContext = createContext<PlayerValue | null>(null)
const ProgressContext = createContext<Progress | null>(null)
const STORAGE_KEY = 'bilimusic_player_state'

function restore(): Saved {
  const fallback: Saved = { currentTrack: null, queue: [], progress: 0, volume: 80, isMuted: false, repeatMode: 'none', isShuffled: false }
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') as Partial<Saved>
    return { ...fallback, ...saved, queue: uniqueTracks(Array.isArray(saved.queue) ? saved.queue : []), progress: Math.max(0, Number(saved.progress) || 0) }
  } catch { return fallback }
}

export function PlayerProvider({ children }: { children: ReactNode }) {
  const initial = useRef(restore()).current
  const { settings } = useAppSettings()
  const [queue, setQueue] = useState(initial.queue)
  const [currentTrack, setCurrentTrack] = useState(initial.currentTrack)
  const [progress, setProgress] = useState(initial.progress)
  const [duration, setDuration] = useState(initial.currentTrack?.duration || 0)
  const [isPlaying, setIsPlaying] = useState(false)
  const [loadingAudio, setLoadingAudio] = useState(false)
  const [volume, setVolume] = useState(initial.volume)
  const [isMuted, setIsMuted] = useState(initial.isMuted)
  const [repeatMode, setRepeatMode] = useState<RepeatMode>(initial.repeatMode)
  const [isShuffled, setIsShuffled] = useState(initial.isShuffled)
  const [toast, setToast] = useState('')
  const queueRef = useRef(queue)
  const state = useRef({ currentTrack, progress, isPlaying, volume, isMuted, repeatMode, isShuffled, autoPlay: settings.autoPlay })
  queueRef.current = queue
  state.current = { currentTrack, progress, isPlaying, volume, isMuted, repeatMode, isShuffled, autoPlay: settings.autoPlay }
  const audio = useRef<HTMLAudioElement | null>(null)
  const generation = useRef(0)
  const autoplay = useRef(false)
  const toastTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)

  const showToast = useCallback((message: string) => {
    setToast(message); clearTimeout(toastTimer.current)
    toastTimer.current = setTimeout(() => setToast(''), 3500)
  }, [])
  const native = useCallback((task: Promise<unknown>) => {
    void task.catch(error => {
      setLoadingAudio(false); setIsPlaying(false)
      showToast(error instanceof Error ? error.message : '播放失败，请重试')
    })
  }, [showToast])

  const commit = useCallback((tracks: Track[], selectedId: string | null, playing: boolean, position = 0) => {
    const next = uniqueTracks(tracks)
    const selected = next.find(track => track.id === selectedId) || next[0] || null
    const previousId = state.current.currentTrack?.id
    queueRef.current = next
    setQueue(next); setCurrentTrack(selected); setProgress(position)
    autoplay.current = playing
    state.current = { ...state.current, currentTrack: selected, progress: position, isPlaying: playing && Boolean(selected) }
    if (isNativeIOS) {
      const options = state.current
      setLoadingAudio(Boolean(selected))
      native(NativePlayer.setQueue({
        tracks: next, startIndex: Math.max(0, next.findIndex(track => track.id === selected?.id)),
        position, autoplay: playing, repeatMode: options.repeatMode, shuffled: options.isShuffled,
        autoPlay: options.autoPlay, volume: options.volume / 100, muted: options.isMuted,
      }))
    } else if (!selected) { audio.current?.pause(); setIsPlaying(false) }
    else if (selected.id === previousId && audio.current?.src && playing) native(audio.current.play())
  }, [native])

  useEffect(() => {
    if (!isNativeIOS) return
    let disposed = false
    const update = (snapshot: NativePlaybackState) => {
      if (disposed || (!snapshot.trackId && queueRef.current.length)) return
      const track = queueRef.current.find(item => item.id === snapshot.trackId) || null
      if (track) {
        if (state.current.currentTrack?.id !== track.id) addRecentTrack(track)
        setCurrentTrack(track)
      } else if (!queueRef.current.length) setCurrentTrack(null)
      setProgress(Math.max(0, snapshot.position)); setDuration(Math.max(0, snapshot.duration))
      setIsPlaying(snapshot.isPlaying); setLoadingAudio(snapshot.isLoading)
      if (snapshot.error) showToast(snapshot.error)
    }
    const listener = NativePlayer.addListener('playerState', update)
    void NativePlayer.getState().then(snapshot => {
      if (disposed) return
      if (snapshot.trackId) update(snapshot)
      else if (initial.queue.length) commit(initial.queue, initial.currentTrack?.id || null, false, initial.progress)
    }).catch(error => showToast(String(error)))
    const refresh = () => { if (!document.hidden) void NativePlayer.getState().then(update).catch(() => {}) }
    document.addEventListener('visibilitychange', refresh)
    return () => { disposed = true; void listener.then(handle => handle.remove()); document.removeEventListener('visibilitychange', refresh) }
  }, [commit, initial, showToast])

  useEffect(() => {
    if (isNativeIOS) native(NativePlayer.configure({ repeatMode, shuffled: isShuffled, autoPlay: settings.autoPlay, volume: volume / 100, muted: isMuted }))
    else if (audio.current) { audio.current.volume = volume / 100; audio.current.muted = isMuted }
  }, [repeatMode, isShuffled, settings.autoPlay, volume, isMuted, native])

  const skip = useCallback((step: number, ended = false) => {
    if (isNativeIOS) { native(step > 0 ? NativePlayer.next() : NativePlayer.previous()); return }
    const options = state.current, tracks = queueRef.current
    if (!tracks.length || (ended && !options.autoPlay && options.repeatMode !== 'one')) { setIsPlaying(false); return }
    const index = tracks.findIndex(track => track.id === options.currentTrack?.id)
    if (ended && options.repeatMode === 'one') {
      if (audio.current) { audio.current.currentTime = 0; native(audio.current.play()) }
      return
    }
    if (ended && index === tracks.length - 1 && options.repeatMode === 'none' && !options.isShuffled) { setIsPlaying(false); return }
    let nextIndex = (index + step + tracks.length) % tracks.length
    if (options.isShuffled && tracks.length > 1) {
      do { nextIndex = Math.floor(Math.random() * tracks.length) } while (nextIndex === index)
    }
    commit(tracks, tracks[nextIndex].id, true)
  }, [commit, native])

  useEffect(() => {
    if (isNativeIOS) return
    const element = new Audio()
    audio.current = element
    const onTime = () => setProgress(element.currentTime)
    const onDuration = () => setDuration(Number.isFinite(element.duration) ? element.duration : 0)
    const onEnded = () => skip(1, true)
    const onPlay = () => setIsPlaying(true)
    const onPause = () => setIsPlaying(false)
    element.addEventListener('timeupdate', onTime); element.addEventListener('loadedmetadata', onDuration)
    element.addEventListener('ended', onEnded); element.addEventListener('play', onPlay); element.addEventListener('pause', onPause)
    return () => { element.pause(); element.src = ''; audio.current = null }
  }, [skip])

  useEffect(() => {
    if (isNativeIOS || !currentTrack || !audio.current) return
    const request = ++generation.current, track = currentTrack, element = audio.current
    setLoadingAudio(true)
    void extractAudio(track.bvid || track.id, track.aid && track.cid ? { aid: track.aid, cid: track.cid } : undefined).then(async source => {
      if (request !== generation.current) return
      element.src = source.audioUrl; element.currentTime = state.current.progress
      setDuration(source.duration || track.duration)
      if (autoplay.current) await element.play()
      addRecentTrack(track)
    }).catch(error => {
      if (request === generation.current) { setIsPlaying(false); showToast(String(error)) }
    }).finally(() => { if (request === generation.current) setLoadingAudio(false) })
    return () => { generation.current++ }
  }, [currentTrack?.id, currentTrack?.bvid, showToast])

  const play = useCallback((track: Track) => { addRecentTrack(track); commit(uniqueTracks([...queueRef.current, track]), track.id, true) }, [commit])
  const pause = useCallback(() => {
    autoplay.current = false
    if (isNativeIOS) native(NativePlayer.pause()); else audio.current?.pause()
    setIsPlaying(false)
  }, [native])
  const togglePlay = useCallback(() => {
    const options = state.current
    if (!options.currentTrack) return
    if (options.isPlaying) { pause(); return }
    autoplay.current = true
    if (isNativeIOS) native(NativePlayer.play())
    else if (audio.current?.src) native(audio.current.play())
    else commit(queueRef.current, options.currentTrack.id, true, options.progress)
  }, [commit, native, pause])
  const next = useCallback(() => skip(1), [skip])
  const prev = useCallback(() => skip(-1), [skip])
  const seek = useCallback((position: number) => {
    const value = Math.max(0, position); setProgress(value)
    if (isNativeIOS) native(NativePlayer.seek({ position: value })); else if (audio.current) audio.current.currentTime = value
  }, [native])
  const edit = useCallback((tracks: Track[]) => {
    const options = state.current
    const retainsCurrent = tracks.some(track => track.id === options.currentTrack?.id)
    commit(tracks, options.currentTrack?.id || null, options.isPlaying, retainsCurrent ? options.progress : 0)
  }, [commit])
  const playNow = useCallback((track: Track) => { addRecentTrack(track); commit([track, ...queueRef.current.filter(item => item.id !== track.id)], track.id, true) }, [commit])
  const playNext = useCallback((track: Track) => { const current = state.current.currentTrack; if (!current) playNow(track); else edit(insertNext(queueRef.current, current.id, track)) }, [edit, playNow])
  const addToQueue = useCallback((track: Track) => { edit(uniqueTracks([...queueRef.current, track])); showToast('已加入播放队列') }, [edit, showToast])
  const addTracksToQueue = useCallback((tracks: Track[]) => edit(uniqueTracks([...queueRef.current, ...tracks])), [edit])
  const removeFromQueue = useCallback((id: string) => edit(queueRef.current.filter(track => track.id !== id)), [edit])
  const removeMultipleFromQueue = useCallback((ids: string[]) => edit(queueRef.current.filter(track => !ids.includes(track.id))), [edit])
  const moveInQueue = useCallback((from: number, to: number) => edit(moveTrack(queueRef.current, from, to)), [edit])
  const clearQueue = useCallback(() => commit([], null, false), [commit])
  const toggleLike = useCallback((id: string) => {
    const track = queueRef.current.find(item => item.id === id)
    if (!track) return
    const liked = new Set(toggleFavoriteTrack(track).map(item => item.id))
    const updated = queueRef.current.map(item => ({ ...item, isLiked: liked.has(item.id) }))
    queueRef.current = updated; setQueue(updated)
    setCurrentTrack(previous => previous ? { ...previous, isLiked: liked.has(previous.id) } : null)
  }, [])
  const playAll = useCallback((tracks: Track[]) => {
    const favorites = new Set(loadFavoriteTracks().map(track => track.id))
    const synced = tracks.map(track => ({ ...track, isLiked: favorites.has(track.id) }))
    if (synced.length) { addRecentTrack(synced[0]); commit(synced, synced[0].id, true) }
  }, [commit])
  const playFromQueue = useCallback((index: number) => { const track = queueRef.current[index]; if (track) play(track) }, [play])

  useEffect(() => {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ currentTrack, queue, progress, volume, isMuted, repeatMode, isShuffled })) } catch { /* storage may be full */ }
  }, [currentTrack, queue, progress, volume, isMuted, repeatMode, isShuffled])
  useEffect(() => () => clearTimeout(toastTimer.current), [])

  const value = useMemo<PlayerValue>(() => ({
    currentTrack, queue, isPlaying, loadingAudio, volume, isMuted, repeatMode, isShuffled,
    play, pause, togglePlay, next, prev, setVolume, setIsMuted, setRepeatMode, setIsShuffled,
    addToQueue, addTracksToQueue, removeFromQueue, removeMultipleFromQueue, moveInQueue,
    playNow, playNext, clearQueue, toggleLike, playAll, playFromQueue,
  }), [currentTrack, queue, isPlaying, loadingAudio, volume, isMuted, repeatMode, isShuffled, play, pause, togglePlay, next, prev, addToQueue, addTracksToQueue, removeFromQueue, removeMultipleFromQueue, moveInQueue, playNow, playNext, clearQueue, toggleLike, playAll, playFromQueue])
  const progressValue = useMemo(() => ({ progress, duration, setProgress: seek }), [progress, duration, seek])
  return <PlayerContext.Provider value={value}><ProgressContext.Provider value={progressValue}>{children}{toast && <div className="mobile-toast" role="status">{toast}</div>}</ProgressContext.Provider></PlayerContext.Provider>
}

export function usePlayer() { const context = useContext(PlayerContext); if (!context) throw new Error('PlayerProvider is missing'); return context }
export function usePlayerProgress() { const context = useContext(ProgressContext); if (!context) throw new Error('PlayerProvider is missing'); return context }

