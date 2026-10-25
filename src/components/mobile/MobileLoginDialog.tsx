import { useState } from 'react'
import { X, LogIn } from 'lucide-react'
import { BiliBridge, isNativeIOS } from '@/platform/native'

export default function MobileLoginDialog({ onClose, onSuccess }: { onClose: () => void; onSuccess: () => void }) {
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const login = async () => {
    if (!isNativeIOS) { setMessage('请在 iPhone 应用中登录。'); return }
    setBusy(true)
    try { if ((await BiliBridge.login()).isLoggedIn) onSuccess(); else setMessage('尚未完成登录，可以重试。') }
    catch (error) { setMessage(error instanceof Error ? error.message : '登录未完成，请重试。') }
    finally { setBusy(false) }
  }
  return <div className="mobile-modal-backdrop"><section className="mobile-login" role="dialog" aria-modal="true" aria-label="登录 Bilibili">
    <button className="mobile-icon close-sheet" aria-label="关闭" onClick={onClose}><X /></button>
    <LogIn size={36} /><h2>登录 Bilibili</h2><p>在 Bilibili 登录页面完成验证，返回后即可使用你的账号。</p>
    <button className="mobile-primary" disabled={busy} onClick={() => void login()}>{busy ? '正在登录…' : '前往登录'}</button>
    {message && <p role="status">{message}</p>}
  </section></div>
}
