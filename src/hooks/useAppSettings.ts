import { useEffect, useState } from 'react'
import {
  loadAppSettings,
  SETTINGS_CHANGED_EVENT,
  updateAppSettings,
} from '@/utils/storage'
import type { AppSettings } from '@/types'

export function useAppSettings() {
  const [settings, setSettings] = useState<AppSettings>(() => loadAppSettings())

  useEffect(() => {
    const sync = () => setSettings(loadAppSettings())
    window.addEventListener(SETTINGS_CHANGED_EVENT, sync)
    window.addEventListener('storage', sync)
    return () => {
      window.removeEventListener(SETTINGS_CHANGED_EVENT, sync)
      window.removeEventListener('storage', sync)
    }
  }, [])

  const setAppSettings = (patch: Partial<AppSettings>) => {
    const next = updateAppSettings(patch)
    setSettings(next)
  }

  return { settings, setAppSettings }
}
