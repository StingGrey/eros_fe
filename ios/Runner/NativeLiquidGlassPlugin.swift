import Flutter
import UIKit

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
        visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: Self.blurStyle(from: params?["fallbackStyle"])))
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

        containerView.addSubview(visualEffectView)
        visualEffectView.contentView.addSubview(overlayView)
    }

    func view() -> UIView {
        containerView
    }

    private static func blurStyle(from value: Any?) -> UIBlurEffect.Style {
        switch value as? String {
        case "systemMaterial":
            return .systemMaterial
        case "systemThinMaterial":
            return .systemThinMaterial
        case "systemChromeMaterial":
            return .systemChromeMaterial
        default:
            return .systemUltraThinMaterial
        }
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
