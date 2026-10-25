import type { Track } from '@/types'

export function uniqueTracks(tracks: Track[]): Track[] {
  const ids = new Set<string>()
  return tracks.filter(track => {
    if (!track?.id || ids.has(track.id)) return false
    ids.add(track.id)
    return true
  })
}

export function moveTrack(queue: Track[], from: number, to: number): Track[] {
  if (from < 0 || to < 0 || from >= queue.length || to >= queue.length || from === to) return queue
  const result = [...queue]
  const [track] = result.splice(from, 1)
  result.splice(to, 0, track)
  return result
}

export function insertNext(queue: Track[], currentId: string, track: Track): Track[] {
  if (track.id === currentId) return queue
  const result = queue.filter(item => item.id !== track.id)
  const index = result.findIndex(item => item.id === currentId)
  result.splice(index < 0 ? result.length : index + 1, 0, track)
  return result
}
