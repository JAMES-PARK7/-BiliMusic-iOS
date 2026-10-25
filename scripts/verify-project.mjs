import fs from 'node:fs'
import assert from 'node:assert/strict'

const read = name => fs.readFileSync(new URL('../' + name, import.meta.url), 'utf8')
const project = read('ios/App/App.xcodeproj/project.pbxproj')
const plist = read('ios/App/App/Info.plist')
const bridge = read('ios/App/App/AppBridgeViewController.swift')
for (const name of ['NativePlayerPlugin', 'BiliBridgePlugin', 'BiliNetwork', 'MediaResourceLoader', 'AppBridgeViewController']) {
  assert.ok(project.includes(name + '.swift in Sources'), name + ' must be compiled into the iOS target')
}
assert.match(plist, /UIBackgroundModes[\s\S]*?<string>audio<\/string>/)
assert.match(plist, /UIFileSharingEnabled/)
assert.match(bridge, /registerPluginInstance\(NativePlayerPlugin\(\)\)/)
assert.match(bridge, /registerPluginInstance\(BiliBridgePlugin\(\)\)/)
assert.match(read('ios/App/App/Base.lproj/Main.storyboard'), /customClass="AppBridgeViewController"/)
assert.match(read('ios/App/App/SceneDelegate.swift'), /rootViewController = AppBridgeViewController\(\)/, 'Scene-based startup must load the custom native plugins')
assert.ok(!/[A-Z]:[\\/]/.test(project), 'Xcode project must not contain Windows build paths')
assert.ok(!read('package.json').includes('electron'), 'iOS package must not depend on Electron')
assert.match(read('dist/index.html'), /viewport-fit=cover/)
console.log('iOS project references, background audio, plugins, portable paths and web assets verified')
