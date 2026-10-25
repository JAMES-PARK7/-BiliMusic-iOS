import { NavLink } from 'react-router-dom'
import { Clock, Heart, Download, ListMusic } from 'lucide-react'
import Playlists from './Playlists'

export default function Library() {
  return <><section className="mobile-library-shortcuts">
    <NavLink to="/favorites"><Heart />我喜欢</NavLink>
    <NavLink to="/recent"><Clock />最近播放</NavLink>
    <NavLink to="/downloads"><Download />本地下载</NavLink>
    <NavLink to="/playlists"><ListMusic />所有歌单</NavLink>
  </section><Playlists /></>
}
