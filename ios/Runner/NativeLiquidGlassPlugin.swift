import Flutter
import UIKit
import Darwin

final class NativeLiquidGlassPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = NativeLiquidGlassViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "eros_fe/native_liquid_glass")
    }
}

private final class NativeLiquidGlassViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        NativeLiquidGlassPlatformView(frame: frame, arguments: args)
    }
}

private final class NativeLiquidGlassPlatformView: NSObject, FlutterPlatformView {
    private let containerView: UIView
    private let visualEffectView: UIVisualEffectView
    private let overlayView: UIView

    init(frame: CGRect, arguments args: Any?) {
        let params = args as? [String: Any]
        containerView = UIView(frame: frame)
        visualEffectView = UIVisualEffectView(effect: Self.makeEffect(params: params))
        overlayView = UIView(frame: .zero)

        super.init()

        containerView.isUserInteractionEnabled = false
        containerView.clipsToBounds = true
        containerView.backgroundColor = .clear

        visualEffectView.frame = containerView.bounds
        visualEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        visualEffectView.isUserInteractionEnabled = false
        visualEffectView.backgroundColor = .clear

        overlayView.frame = containerView.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.isUserInteractionEnabled = false
        overlayView.backgroundColor = Self.color(from: params?["overlayColor"])

        if let cornerRadius = params?["cornerRadius"] as? NSNumber {
            containerView.layer.cornerRadius = CGFloat(truncating: cornerRadius)
            containerView.layer.cornerCurve = .continuous
        }

        if #available(iOS 26.0, *),
           let glassEffect = visualEffectView.effect,
           glassEffect.isKind(of: NSClassFromString("UIGlassEffect") ?? UIVisualEffect.self) {
            if let tintColor = Self.color(from: params?["tintColor"]) {
                setGlassTintColor(tintColor, on: glassEffect)
            }
            if let isInteractive = (params?["isInteractive"] as? NSNumber)?.boolValue {
                setGlassIsInteractive(isInteractive, on: glassEffect)
            }
        }

        containerView.addSubview(visualEffectView)
        visualEffectView.contentView.addSubview(overlayView)
    }

    func view() -> UIView {
        containerView
    }

    private static func makeEffect(params: [String: Any]?) -> UIVisualEffect? {
        if #available(iOS 26.0, *),
           let glassEffect = makeGlassEffect(params: params) {
            return glassEffect
        }

        switch params?["fallbackStyle"] as? String {
        case "systemMaterial":
            return UIBlurEffect(style: .systemMaterial)
        case "systemThinMaterial":
            return UIBlurEffect(style: .systemThinMaterial)
        case "systemChromeMaterial":
            return UIBlurEffect(style: .systemChromeMaterial)
        default:
            return UIBlurEffect(style: .systemUltraThinMaterial)
        }
    }

    @available(iOS 26.0, *)
    private static func makeGlassEffect(params: [String: Any]?) -> UIVisualEffect? {
        guard let glassClass = NSClassFromString("UIGlassEffect") as? AnyClass else {
            return nil
        }

        // Keep all UIGlassEffect calls dynamic so this target still compiles
        // with older Xcode SDKs. On iOS 26+ the runtime class exposes
        // init(style:), tintColor and isInteractive.
        let styleName = (params?["style"] as? String) ?? "regular"
        let styleRawValue = styleName == "clear" ? 0 : 1
        let allocSelector = NSSelectorFromString("alloc")
        let initSelector = NSSelectorFromString("initWithStyle:")

        guard let allocated = sendClassMessage(glassClass, selector: allocSelector),
              let effect = sendObjectMessage(allocated, selector: initSelector, intArgument: styleRawValue) else {
            return nil
        }

        return effect as? UIVisualEffect
    }

    @available(iOS 26.0, *)
    private func setGlassTintColor(_ tintColor: UIColor, on effect: UIVisualEffect) {
        setObjectValue(tintColor, selectorName: "setTintColor:", on: effect)
    }

    @available(iOS 26.0, *)
    private func setGlassIsInteractive(_ isInteractive: Bool, on effect: UIVisualEffect) {
        setBoolValue(isInteractive, selectorName: "setIsInteractive:", on: effect)
    }

    private static func sendClassMessage(_ receiver: AnyClass, selector: Selector) -> AnyObject? {
        guard let msgSend = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") else {
            return nil
        }

        typealias Message = @convention(c) (AnyClass, Selector) -> AnyObject?
        let function = unsafeBitCast(msgSend, to: Message.self)
        return function(receiver, selector)
    }

    private static func sendObjectMessage(_ receiver: AnyObject, selector: Selector, intArgument: Int) -> AnyObject? {
        guard let msgSend = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") else {
            return nil
        }

        typealias Message = @convention(c) (AnyObject, Selector, Int) -> AnyObject?
        let function = unsafeBitCast(msgSend, to: Message.self)
        return function(receiver, selector, intArgument)
    }

    private func setObjectValue(_ value: AnyObject, selectorName: String, on object: NSObject) {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let msgSend = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") else {
            return
        }

        typealias Setter = @convention(c) (NSObject, Selector, AnyObject) -> Void
        let setter = unsafeBitCast(msgSend, to: Setter.self)
        setter(object, selector, value)
    }

    private func setBoolValue(_ value: Bool, selectorName: String, on object: NSObject) {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let msgSend = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") else {
            return
        }

        typealias Setter = @convention(c) (NSObject, Selector, Bool) -> Void
        let setter = unsafeBitCast(msgSend, to: Setter.self)
        setter(object, selector, value)
    }

    private static func color(from value: Any?) -> UIColor? {
        guard let number = value as? NSNumber else {
            return nil
        }

        let argb = number.uint32Value
        let alpha = CGFloat((argb >> 24) & 0xff) / 255.0
        let red = CGFloat((argb >> 16) & 0xff) / 255.0
        let green = CGFloat((argb >> 8) & 0xff) / 255.0
        let blue = CGFloat(argb & 0xff) / 255.0

        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
