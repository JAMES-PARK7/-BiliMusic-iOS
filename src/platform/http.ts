import { BiliBridge, isNativeIOS } from './native'

const proxyOrigins: Record<string, string> = {
  'api.bilibili.com': '/__bili',
  'passport.bilibili.com': '/__passport',
  'www.oiapi.net': '/__lyrics',
}

export function previewURL(value: string): string {
  const url = new URL(value)
  const prefix = proxyOrigins[url.hostname]
  if (url.protocol !== 'https:' || !prefix) throw new Error('不支持的 API 地址')
  return prefix + url.pathname + url.search
}

export async function apiFetch(input: string | URL, init?: RequestInit): Promise<Pick<Response, 'json' | 'ok' | 'status'>> {
  const url = String(input)
  if (isNativeIOS) {
    const response = await BiliBridge.request({ url })
    if (response.status < 200 || response.status >= 300) throw new Error(`网络请求失败（${response.status}）`)
    return { status: response.status, ok: true, json: async () => response.data }
  }
  return window.fetch(previewURL(url), { ...init, headers: undefined, credentials: 'include' })
}
