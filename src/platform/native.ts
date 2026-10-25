import { Capacitor, registerPlugin, type PluginListenerHandle } from '@capacitor/core'
import type { Track, RepeatMode } from '@/types'

export const isNativeIOS = Capacitor.getPlatform() === 'ios'

export interface NativePlaybackState {
  trackId: string
  isPlaying: boolean
  position: number
  duration: number
  isLoading: boolean
  error?: string
}

export interface NativeQueueOptions {
  tracks: Track[]
  startIndex: number
  position: number
  autoplay: boolean
  repeatMode: RepeatMode
  shuffled: boolean
  autoPlay: boolean
  volume: number
  muted: boolean
}

interface NativePlayerAPI {
  setQueue(options: NativeQueueOptions): Promise<void>
  play(): Promise<void>
  pause(): Promise<void>
  next(): Promise<void>
  previous(): Promise<void>
  seek(options: { position: number }): Promise<void>
  configure(options: { repeatMode: RepeatMode; shuffled: boolean; autoPlay: boolean; volume: number; muted: boolean }): Promise<void>
  getState(): Promise<NativePlaybackState>
  addListener(event: 'playerState', callback: (state: NativePlaybackState) => void): Promise<PluginListenerHandle>
}

export interface DownloadedFile { name: string; size: number }
interface BiliBridgeAPI {
  request(options: { url: string }): Promise<{ status: number; data: unknown }>
  login(): Promise<{ isLoggedIn: boolean }>
  sessionStatus(): Promise<{ isLoggedIn: boolean }>
  logout(): Promise<void>
  download(options: { track: Track }): Promise<DownloadedFile>
  files(): Promise<{ files: DownloadedFile[] }>
  shareFile(options: { name: string }): Promise<void>
  exportText(options: { content: string }): Promise<void>
}

export const NativePlayer = registerPlugin<NativePlayerAPI>('NativePlayer')
export const BiliBridge = registerPlugin<BiliBridgeAPI>('BiliBridge')
