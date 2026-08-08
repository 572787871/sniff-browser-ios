import UIKit

/// 简单的水平平移转场：push 从右侧滑入、pop 滑出到右侧。
///
/// 不做视差、缩放或其它附加动作，保持与 iOS 系统转场一致但更克制。
/// Reduce Motion 下退化为快速淡切。
final class NavigationTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let operation: UINavigationController.Operation

    init(operation: UINavigationController.Operation) {
        self.operation = operation
        super.init()
    }

    func transitionDuration(
        using transitionContext: UIViewControllerContextTransitioning?
    ) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.28
    }

    func animateTransition(
        using transitionContext: UIViewControllerContextTransitioning
    ) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toViewController = transitionContext.viewController(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        let width = container.bounds.width
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let duration = transitionDuration(using: transitionContext)

        switch operation {
        case .push:
            container.addSubview(toView)
            toView.frame = transitionContext.finalFrame(for: toViewController)
            toView.alpha = reduceMotion ? 0 : 1
            toView.transform = reduceMotion
                ? .identity
                : CGAffineTransform(translationX: width, y: 0)
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    toView.transform = .identity
                    toView.alpha = 1
                },
                completion: { _ in
                    transitionContext.completeTransition(
                        !transitionContext.transitionWasCancelled
                    )
                }
            )
        case .pop:
            container.insertSubview(toView, belowSubview: fromView)
            toView.frame = transitionContext.finalFrame(for: toViewController)
            toView.alpha = 1
            fromView.alpha = reduceMotion ? 0 : 1
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    fromView.transform = reduceMotion
                        ? .identity
                        : CGAffineTransform(translationX: width, y: 0)
                    fromView.alpha = reduceMotion ? 0 : 1
                },
                completion: { _ in
                    if transitionContext.transitionWasCancelled {
                        fromView.transform = .identity
                        fromView.alpha = 1
                    }
                    transitionContext.completeTransition(
                        !transitionContext.transitionWasCancelled
                    )
                }
            )
        default:
            transitionContext.completeTransition(false)
        }
    }
}
