import type { CapacitorConfig } from '@capacitor/cli'

const config: CapacitorConfig = {
  appId: 'com.hanversion.bilimusic.ios',
  appName: 'BiliMusic',
  webDir: 'dist',
  ios: { contentInset: 'never', backgroundColor: '#f8f8fa', preferredContentMode: 'mobile' },
}

export default config
