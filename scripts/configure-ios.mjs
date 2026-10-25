import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
const require = createRequire(import.meta.url)
const xcode = require('xcode')
const { PNG } = require('pngjs')
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const projectPath = path.join(root, 'ios/App/App.xcodeproj/project.pbxproj')
const project = xcode.project(projectPath)
project.parseSync()
const group = Object.entries(project.hash.project.objects.PBXGroup).find(([, value]) => value && typeof value === 'object' && value.path === 'App')?.[0]
if (!group) throw new Error('App group was not found')
const target = project.getFirstTarget().uuid
for (const name of ['BiliNetwork.swift', 'MediaResourceLoader.swift', 'NativePlayerPlugin.swift', 'BiliBridgePlugin.swift', 'AppBridgeViewController.swift']) {
  if (!project.hasFile(name)) project.addSourceFile(name, { target }, group)
}
for (const value of Object.values(project.hash.project.objects.PBXFileReference)) {
  if (value && typeof value === 'object') for (const key of Object.keys(value)) if (value[key] === undefined || value[key] === 'undefined') delete value[key]
}
fs.writeFileSync(projectPath, project.writeSync())
const storyboard = path.join(root, 'ios/App/App/Base.lproj/Main.storyboard')
fs.writeFileSync(storyboard, fs.readFileSync(storyboard, 'utf8').replace('customClass="CAPBridgeViewController" customModule="Capacitor"', 'customClass="AppBridgeViewController" customModule="App" customModuleProvider="target"'))
const scenePath = path.join(root, 'ios/App/App/SceneDelegate.swift')
fs.writeFileSync(scenePath, fs.readFileSync(scenePath, 'utf8').replace('rootViewController = CAPBridgeViewController()', 'rootViewController = AppBridgeViewController()'))
const plistPath = path.join(root, 'ios/App/App/Info.plist')
let plist = fs.readFileSync(plistPath, 'utf8').replace(/\r\n/g, '\n')
if (!plist.includes('<key>UIBackgroundModes</key>')) plist = plist.replace('</dict>\n</plist>', '<key>UIBackgroundModes</key><array><string>audio</string></array>\n<key>UIFileSharingEnabled</key><true/>\n<key>LSSupportsOpeningDocumentsInPlace</key><true/>\n</dict>\n</plist>')
plist = plist.replace('<string>armv7</string>', '<string>arm64</string>')
fs.writeFileSync(plistPath, plist)
const icon = PNG.sync.read(fs.readFileSync(path.join(root, 'src/assets/icon.png')))
const resized = new PNG({ width: 1024, height: 1024 })
for (let y = 0; y < 1024; y++) for (let x = 0; x < 1024; x++) {
  const from = (Math.floor(y * icon.height / 1024) * icon.width + Math.floor(x * icon.width / 1024)) * 4
  const to = (y * 1024 + x) * 4
  const alpha = icon.data[from + 3] / 255
  for (let channel = 0; channel < 3; channel++) resized.data[to + channel] = Math.round(icon.data[from + channel] * alpha + 255 * (1 - alpha))
  resized.data[to + 3] = 255
}
fs.writeFileSync(path.join(root, 'ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png'), PNG.sync.write(resized))
console.log('iOS native sources, background audio, sandbox files and app icon configured')
