import { ListPlus } from 'lucide-react'
import { useAddToPlaylist } from '@/contexts/AddToPlaylistContext'
import type { Track } from '@/types'

export default function AddToPlaylistButton({ track, size = 16 }: { track: Track; size?: number }) {
  const { openAddToPlaylist } = useAddToPlaylist()

  return (
    <button
      type="button"
      className="track-action-button"
      title="添加至歌单"
      onClick={(e) => {
        e.stopPropagation()
        openAddToPlaylist(track)
      }}
    >
      <ListPlus size={size} />
    </button>
  )
}
