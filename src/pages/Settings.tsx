import { useState } from 'react'
import { Download, Upload, LogIn, LogOut } from 'lucide-react'
import { useTheme } from '@/hooks/useTheme'
import { useAppSettings } from '@/hooks/useAppSettings'
import { useAuth } from '@/contexts/AuthContext'
import { createPlaylistsExport, importPlaylistsFromText } from '@/utils/storage'
import { BiliBridge, isNativeIOS } from '@/platform/native'
import type { ThemeMode } from '@/types'

export default function Settings() {
  const { mode, setMode } = useTheme()
  const { settings, setAppSettings } = useAppSettings()
  const auth = useAuth()
  const [message, setMessage] = useState('')
  const exportLibrary = async () => {
    const content = JSON.stringify(createPlaylistsExport(), null, 2)
    if (isNativeIOS) { await BiliBridge.exportText({ content }); return }
    const anchor = document.createElement('a')
    anchor.href = URL.createObjectURL(new Blob([content], { type: 'application/json' }))
    anchor.download = 'BiliMusic-playlists.json'; anchor.click(); URL.revokeObjectURL(anchor.href)
  }
  return <article className="mobile-settings"><h1>设置</h1>
    <section><h2>账号</h2><div className="mobile-settings-row"><strong>{auth.isLoggedIn ? auth.username : '尚未登录'}</strong><span>Bilibili</span></div>
      {auth.isLoggedIn ? <button onClick={() => void auth.logout()}><LogOut size={18} />退出账号</button> : <button onClick={() => auth.setShowLogin(true)}><LogIn size={18} />登录 Bilibili</button>}
    </section>
    <section><h2>外观与播放</h2><label>主题<select value={mode} onChange={event => setMode(event.target.value as ThemeMode)}><option value="system">跟随系统</option><option value="light">浅色</option><option value="dark">深色</option></select></label>
      <label>连续播放<input type="checkbox" checked={settings.autoPlay} onChange={event => setAppSettings({ autoPlay: event.target.checked })} /></label>
      <p>关闭连续播放后，当前歌曲结束时停止。单曲循环仍按循环设置播放。</p>
    </section>
    <section><h2>歌单备份</h2><button onClick={() => void exportLibrary().catch(error => setMessage(String(error)))}><Upload size={18} />导出歌单</button>
      <label className="file-import"><Download size={18} />导入歌单<input type="file" accept=".json,application/json" onChange={event => { const file = event.target.files?.[0]; if (file) void file.text().then(text => { const result = importPlaylistsFromText(text); setMessage('已导入 ' + result.imported + ' 个歌单') }).catch(error => setMessage(String(error))); event.target.value = '' }} /></label>
      {message && <p role="status">{message}</p>}
    </section>
    <section><h2>存储</h2><p>下载的音频保存在“文件”App → 我的 iPhone → BiliMusic → BiliMusic。可在“资料库 → 本地下载”中分享文件。</p></section>
    <section><h2>关于</h2><div className="mobile-settings-row"><strong>BiliMusic for iOS</strong><span>1.0.0</span></div><p>基于 HanversionOvO/BiliMusic 的非官方 iPhone 适配版。</p><p>通过 AltStore / Sideloadly 签名侧载安装，签名有效期由你的 Apple 开发者账号决定。</p></section>
  </article>
}

