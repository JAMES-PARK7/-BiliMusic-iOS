import { createContext, useContext, useState, useCallback, type ReactNode } from 'react'

interface NowPlayingContextValue {
  expanded: boolean
  open: () => void
  close: () => void
}

const NowPlayingContext = createContext<NowPlayingContextValue | null>(null)

/** 歌词页（全屏覆盖层）的展开开关。播放栏触发，NowPlaying 消费。 */
export function NowPlayingProvider({ children }: { children: ReactNode }) {
  const [expanded, setExpanded] = useState(false)
  const open = useCallback(() => setExpanded(true), [])
  const close = useCallback(() => setExpanded(false), [])
  return (
    <NowPlayingContext.Provider value={{ expanded, open, close }}>
      {children}
    </NowPlayingContext.Provider>
  )
}

export function useNowPlaying(): NowPlayingContextValue {
  const ctx = useContext(NowPlayingContext)
  if (!ctx) throw new Error('useNowPlaying must be used within NowPlayingProvider')
  return ctx
}
