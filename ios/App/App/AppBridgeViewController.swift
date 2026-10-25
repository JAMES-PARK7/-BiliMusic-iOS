import Capacitor

public class AppBridgeViewController: CAPBridgeViewController {
    override public func capacitorDidLoad() {
        bridge?.registerPluginInstance(BiliBridgePlugin())
        bridge?.registerPluginInstance(NativePlayerPlugin())
    }
}
