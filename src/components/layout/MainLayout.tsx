import { Outlet, NavLink } from 'react-router-dom'
import { Compass, Search, Library, Settings } from 'lucide-react'
import MobilePlayer from '@/components/mobile/MobilePlayer'
import appIcon from '@/assets/icon.png'

export default function MainLayout() {
  return <div className="mobile-shell">
    <header className="mobile-header"><img src={appIcon} alt="" /><strong>BiliMusic</strong><NavLink to="/recommend">为你推荐</NavLink></header>
    <main className="mobile-content"><Outlet /></main>
    <MobilePlayer />
    <nav className="mobile-tabs" aria-label="主导航">
      <NavLink to="/discover"><Compass /><span>发现</span></NavLink>
      <NavLink to="/search"><Search /><span>搜索</span></NavLink>
      <NavLink to="/library"><Library /><span>资料库</span></NavLink>
      <NavLink to="/settings"><Settings /><span>设置</span></NavLink>
    </nav>
  </div>
}

