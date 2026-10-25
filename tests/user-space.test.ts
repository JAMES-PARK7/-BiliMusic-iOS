import { beforeEach, describe, expect, it, vi } from 'vitest'
const { request } = vi.hoisted(() => ({ request: vi.fn() }))
vi.mock('../src/platform/http', () => ({ apiFetch: request }))
import { getUserVideos } from '../src/services/api'

const response = (data: unknown) => ({ status: 200, ok: true, json: async () => ({ code: 0, data }) })
const blocked = () => ({ status: 200, ok: true, json: async () => ({ code: -352, message: '风控校验失败' }) })
const video = (bvid: string, mid = 42) => ({ id: 123, bv_id: bvid, title: '公开投稿', cover: 'http://i0.hdslb.com/cover.png', duration: 379, pubtime: 123456, upper: { mid, name: 'UP' }, cnt_info: { play: 200 } })
const nav = () => response({ wbi_img: { img_url: 'https://i0.hdslb.com/0123456789abcdef0123456789abcdef.png', sub_url: 'https://i0.hdslb.com/fedcba9876543210fedcba9876543210.png' } })
beforeEach(() => { request.mockReset() })

describe('UP upload lists', () => {
  it('loads a public UP playlist without depending on the restricted space endpoint', async () => {
    request.mockResolvedValue(response({ media_list: [video('BV-one')], has_more: true, total_count: 1923 }))
    const result = await getUserVideos(42)
    expect(result.items[0]).toMatchObject({ bvid: 'BV-one', duration: 379, coverUrl: 'https://i0.hdslb.com/cover.png', play: 200 })
    expect(result).toMatchObject({ total: 1923, hasMore: true, nextCursor: 'playlist:BV-one' })
    expect(new URL(request.mock.calls[0][0]).searchParams.get('biz_id')).toBe('42')
    expect(request).toHaveBeenCalledTimes(1)
  })

  it('continues from the last BV cursor instead of requesting the first page again', async () => {
    request.mockResolvedValue(response({ media_list: [video('BV-two')], has_more: false, total_count: 2 }))
    const result = await getUserVideos(42, 2, 30, 'playlist:BV-one')
    expect(new URL(request.mock.calls[0][0]).searchParams.get('bvid')).toBe('BV-one')
    expect(result.items.map(item => item.bvid)).toEqual(['BV-two'])
    expect(result.hasMore).toBe(false)
  })

  it('excludes videos that do not belong to the selected UP', async () => {
    request.mockResolvedValue(response({ media_list: [video('BV-other', 99), video('BV-owned')], has_more: false, total_count: 1 }))
    expect((await getUserVideos(42)).items.map(item => item.bvid)).toEqual(['BV-owned'])
  })

  it('uses the normal upload endpoint if the first playlist request is unavailable', async () => {
    request.mockImplementation(async (url: string) => url.includes('/nav') ? nav() : url.includes('/medialist/') ? blocked() : response({ list: { vlist: [{ bvid: 'BV-upload', title: '投稿', pic: '', length: '1:00', play: 2, created: 3 }] }, page: { count: 31 } }))
    expect(await getUserVideos(42)).toMatchObject({ hasMore: true, nextCursor: 'uploads:2' })
  })

  it('keeps a failed continuation on the same source and offers official verification', async () => {
    request.mockResolvedValue(blocked())
    await expect(getUserVideos(42, 2, 30, 'playlist:BV-one')).rejects.toThrow('官方主页')
    expect(request).toHaveBeenCalledTimes(1)
  })

  it('stops when a broken server repeats the same continuation cursor', async () => {
    request.mockResolvedValue(response({ media_list: [video('BV-one')], has_more: true, total_count: 100 }))
    expect((await getUserVideos(42, 2, 30, 'playlist:BV-one')).hasMore).toBe(false)
  })

  it('does not label an unavailable nonempty account as having no uploads', async () => {
    request.mockImplementation(async (url: string) => url.includes('/nav') ? nav() : url.includes('/medialist/') ? response({ media_list: [], has_more: false, total_count: 1923 }) : blocked())
    await expect(getUserVideos(42)).rejects.toThrow('官方主页')
  })
})
