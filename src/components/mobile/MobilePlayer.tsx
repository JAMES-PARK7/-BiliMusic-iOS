import { useState } from 'react'
import { ChevronDown, Heart, ListMusic, Music2, Pause, Play, Repeat, Repeat1, Shuffle, SkipBack, SkipForward, Download, ListPlus, Mic } from 'lucide-react'
import { usePlayer, usePlayerProgress } from '@/contexts/PlayerContext'
import { useNowPlaying } from '@/contexts/NowPlayingContext'
import { useAddToPlaylist } from '@/contexts/AddToPlaylistContext'
import { BiliBridge, isNativeIOS } from '@/platform/native'
import PlayQueue from '@/components/PlayQueue'
import { useLyrics } from '@/hooks/useLyrics'
import LyricsView from '@/components/LyricsView'

function time(value: number) { const seconds = Math.max(0, Math.floor(value || 0)); return Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0') }

export default function MobilePlayer() {
  const player = usePlayer()
  const { progress, duration, setProgress } = usePlayerProgress()
  const { expanded, open, close } = useNowPlaying()
  const { openAddToPlaylist } = useAddToPlaylist()
  const [queueOpen, setQueueOpen] = useState(false)
  const [downloadMessage, setDownloadMessage] = useState('')
  const track = player.currentTrack
  const [lyricsOpen, setLyricsOpen] = useState(false)
  const lyrics = useLyrics(track, expanded && lyricsOpen)
  const download = async () => {
    if (!track || !isNativeIOS) return
    setDownloadMessage('正在下载…')
    try { await BiliBridge.download({ track }); setDownloadMessage('已保存到“文件”中的 BiliMusic 文件夹') }
    catch (error) { setDownloadMessage(error instanceof Error ? error.message : '下载失败，请重试') }
  }
  return <>
    <section className="mobile-mini-player" aria-label="播放器">
      <button className="mobile-current" onClick={open} aria-label="展开播放器">
        {track?.coverUrl ? <img src={track.coverUrl} alt="" /> : <span className="mobile-cover-placeholder"><Music2 /></span>}
        <span><strong>{track?.title || '挑一首喜欢的音乐'}</strong><small>{player.loadingAudio ? '正在加载…' : track?.artist || '搜索、收藏，随时听'}</small></span>
      </button>
      <button className="mobile-icon" disabled={!track} aria-label={player.isPlaying ? '暂停' : '播放'} onClick={player.togglePlay}>{player.isPlaying ? <Pause fill="currentColor" /> : <Play fill="currentColor" />}</button>
      <button className="mobile-icon" aria-label="播放队列" onClick={() => setQueueOpen(true)}><ListMusic /></button>
      <div className="mini-progress" style={{ width: (duration > 0 ? Math.min(100, progress / duration * 100) : 0) + '%' }} />
    </section>
    {expanded && <section className="mobile-now-playing" role="dialog" aria-modal="true" aria-label="正在播放">
      <header><button className="mobile-icon" aria-label="收起播放器" onClick={close}><ChevronDown /></button><span>正在播放</span><button className="mobile-icon" aria-label="播放队列" onClick={() => setQueueOpen(true)}><ListMusic /></button></header>
      {lyricsOpen ? <div className="mobile-lyrics">{lyrics.result?.lines.length ? <LyricsView lines={lyrics.result.lines} currentTime={progress} synced={lyrics.result.synced} onSeek={setProgress} /> : <p>{lyrics.status === 'loading' ? '正在寻找歌词…' : '暂无匹配歌词'}</p>}</div> : <div className="mobile-album">{track?.coverUrl ? <img src={track.coverUrl} alt={track.title} /> : <Music2 size={80} />}</div>}
      <div className="mobile-track-heading"><div><h1>{track?.title || '未在播放'}</h1><p>{track?.artist || '选择一首音乐开始播放'}</p></div><button className={'mobile-icon ' + (track?.isLiked ? 'is-liked' : '')} disabled={!track} aria-label="喜欢" onClick={() => track && player.toggleLike(track.id)}><Heart fill={track?.isLiked ? 'currentColor' : 'none'} /></button></div>
      <input className="mobile-seek" type="range" aria-label="播放进度" min="0" max={duration || 1} step="0.1" value={Math.min(progress, duration || 1)} onChange={event => setProgress(Number(event.target.value))} />
      <div className="mobile-times"><span>{time(progress)}</span><span>{time(duration)}</span></div>
      <div className="mobile-transport">
        <button className={'mobile-icon ' + (player.isShuffled ? 'is-active' : '')} aria-label="随机播放" onClick={() => player.setIsShuffled(!player.isShuffled)}><Shuffle /></button>
        <button className="mobile-icon" aria-label="上一首" onClick={player.prev}><SkipBack size={34} fill="currentColor" /></button>
        <button className="mobile-play-large" disabled={!track} aria-label={player.isPlaying ? '暂停' : '播放'} onClick={player.togglePlay}>{player.isPlaying ? <Pause size={40} fill="currentColor" /> : <Play size={40} fill="currentColor" />}</button>
        <button className="mobile-icon" aria-label="下一首" onClick={player.next}><SkipForward size={34} fill="currentColor" /></button>
        <button className={'mobile-icon ' + (player.repeatMode !== 'none' ? 'is-active' : '')} aria-label="循环模式" onClick={() => player.setRepeatMode(player.repeatMode === 'none' ? 'all' : player.repeatMode === 'all' ? 'one' : 'none')}>{player.repeatMode === 'one' ? <Repeat1 /> : <Repeat />}</button>
      </div>
      <div className="mobile-player-actions"><button disabled={!track} onClick={() => setLyricsOpen(!lyricsOpen)}><Mic size={20} />歌词</button><button disabled={!track} onClick={() => track && openAddToPlaylist(track)}><ListPlus size={20} />歌单</button><button disabled={!track || !isNativeIOS || downloadMessage === '正在下载…'} onClick={() => void download()}><Download size={20} />下载</button></div>
      {downloadMessage && <p className="mobile-note" role="status">{downloadMessage}</p>}
    </section>}
    <PlayQueue open={queueOpen} onClose={() => setQueueOpen(false)} />
  </>
}
