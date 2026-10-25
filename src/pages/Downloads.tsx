import { useEffect, useState } from 'react'
import { Download, Share2 } from 'lucide-react'
import { BiliBridge, isNativeIOS, type DownloadedFile } from '@/platform/native'

export default function Downloads() {
  const [files, setFiles] = useState<DownloadedFile[]>([])
  const [message, setMessage] = useState('')
  useEffect(() => {
    if (isNativeIOS) void BiliBridge.files().then(result => setFiles(result.files)).catch(error => setMessage(String(error)))
  }, [])
  return <article className="mobile-settings"><h1>本地下载</h1><p>在播放器中点击“下载”，即可保存当前歌曲。</p>
    {files.map(file => <div className="mobile-download" key={file.name}><Download /><div><strong>{file.name}</strong><small>{(file.size / 1024 / 1024).toFixed(1)} MB</small></div><button className="mobile-icon" aria-label={'分享 ' + file.name} onClick={() => void BiliBridge.shareFile({ name: file.name }).catch(error => setMessage(String(error)))}><Share2 /></button></div>)}
    {!files.length && <section><h2>还没有下载的音频</h2><p>保存后可在这里分享，或在 iPhone 的“文件”App 中打开。</p></section>}
    {message && <p role="status">{message}</p>}
  </article>
}

