import { describe, expect, it } from 'vitest'
import { insertNext, moveTrack, uniqueTracks } from '../src/platform/queue'
import { previewURL } from '../src/platform/http'
import type { Track } from '../src/types'

const track = (id: string): Track => ({ id, bvid: id, title: id, artist: '', coverUrl: '', videoUrl: '', duration: 1, playCount: 0, isLiked: false })
const ids = (tracks: Track[]) => tracks.map(item => item.id)

describe('mobile queue editing', () => {
  it('keeps the first metadata record when deduplicating a queue', () => {
    const first = { ...track('A'), title: 'My selected recording' }
    expect(uniqueTracks([first, track('B'), track('A')])).toEqual([first, track('B')])
  })
  it('moves an existing song immediately after the current track without duplicates', () => {
    expect(ids(insertNext(['A', 'B', 'C', 'D'].map(track), 'B', track('D')))).toEqual(['A', 'B', 'D', 'C'])
  })
  it('does not move or duplicate the currently playing song when selecting play-next', () => {
    const original = ['A', 'B'].map(track)
    expect(insertNext(original, 'A', track('A'))).toBe(original)
  })
  it('reorders without mutating the source list', () => {
    const original = ['A', 'B', 'C'].map(track)
    expect(ids(moveTrack(original, 0, 2))).toEqual(['B', 'C', 'A'])
    expect(ids(original)).toEqual(['A', 'B', 'C'])
    expect(moveTrack(original, -1, 2)).toBe(original)
  })
})

describe('development network transport', () => {
  it('preserves signed query strings when routing an API request', () => {
    expect(previewURL('https://api.bilibili.com/x/search?keyword=a%20b&w_rid=abc&wts=123')).toBe('/__bili/x/search?keyword=a%20b&w_rid=abc&wts=123')
  })
  it('rejects other origins and cleartext requests', () => {
    expect(() => previewURL('https://api.bilibili.com.example.org/x')).toThrow()
    expect(() => previewURL('http://api.bilibili.com/x')).toThrow()
    expect(() => previewURL('file:///private/data')).toThrow()
  })
})
