import { beforeEach, describe, expect, it, vi } from 'vitest'
const { request } = vi.hoisted(() => ({ request: vi.fn() }))
vi.mock('../src/platform/http', () => ({ apiFetch: request }))
import { searchVideo, searchUsers } from '../src/services/api'

const row = { bvid: 'BV-test', aid: 1, title: '<em>周杰伦</em> - 晴天', author: '音乐人', play: 123, duration: '4:10', pic: '//i0.hdslb.com/cover.jpg' }
const ok = (data: unknown) => ({ status: 200, ok: true, json: async () => ({ code: 0, data }) })
const nav = () => ok({ wbi_img: { img_url: 'https://i0.hdslb.com/bfs/wbi/0123456789abcdef0123456789abcdef.png', sub_url: 'https://i0.hdslb.com/bfs/wbi/fedcba9876543210fedcba9876543210.png' } })
beforeEach(() => { request.mockReset() })

describe('search response compatibility', () => {
  it('maps a Chinese public search result into a playable result', async () => {
    request.mockResolvedValue(ok({ result: [row], numPages: 2, numResults: 25 }))
    const result = await searchVideo('周杰伦')
    expect(result.items[0]).toMatchObject({ bvid: 'BV-test', title: '周杰伦 - 晴天', pic: 'https://i0.hdslb.com/cover.jpg' })
    expect(result.totalResults).toBe(25)
    expect(new URL(request.mock.calls[0][0]).searchParams.get('keyword')).toBe('周杰伦')
  })

  it('falls back when code=0 contains verification metadata instead of a result list', async () => {
    request.mockImplementation(async (address: string) => address.includes('/nav') ? nav() : address.includes('/wbi/') ? ok({ result: [row], numPages: 1, numResults: 1 }) : ok({ v_voucher: 'not-a-result' }))
    expect((await searchVideo('AIYOU')).items).toHaveLength(1)
    expect(request.mock.calls.some(([address]) => String(address).includes('/wbi/search/type?'))).toBe(true)
  })

  it('reports an unavailable service instead of silently returning zero results', async () => {
    request.mockImplementation(async (address: string) => address.includes('/nav') ? nav() : ok({ v_voucher: 'not-a-result' }))
    await expect(searchVideo('周杰伦')).rejects.toThrow('未返回结果列表')
  })

  it('accepts a genuine empty search without issuing a fallback request', async () => {
    request.mockResolvedValue(ok({ result: [], numPages: 0, numResults: 0 }))
    expect((await searchVideo('不存在的曲目')).items).toEqual([])
    expect(request).toHaveBeenCalledTimes(1)
  })

  it('supports UP search with the same fallback and preserves pagination', async () => {
    request.mockResolvedValue(ok({ result: [{ mid: 123, uname: '<em>Eve</em>', upic: '//i0.hdslb.com/eve.png', fans: 100, videos: 8 }], numPages: 3, numResults: 55 }))
    const result = await searchUsers('Eve', 2)
    expect(result.items[0]).toMatchObject({ mid: 123, name: 'Eve', avatar: 'https://i0.hdslb.com/eve.png' })
    const query = new URL(request.mock.calls[0][0]).searchParams
    expect(query.get('search_type')).toBe('bili_user')
    expect(query.get('page')).toBe('2')
  })
})
