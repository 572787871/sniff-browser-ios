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
            applySlideShadow(to: toView)
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
                    toView.layer.shadowOpacity = 0
                    transitionContext.completeTransition(
                        !transitionContext.transitionWasCancelled
                    )
                }
            )
        case .pop:
            container.insertSubview(toView, belowSubview: fromView)
            toView.frame = transitionContext.finalFrame(for: toViewController)
            toView.alpha = 1
            applySlideShadow(to: fromView)
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
                    fromView.layer.shadowOpacity = 0
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

    private func applySlideShadow(to view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.14
        view.layer.shadowRadius = 6
        view.layer.shadowOffset = CGSize(width: -4, height: 0)
        view.layer.shadowPath = UIBezierPath(
            roundedRect: view.bounds,
            cornerRadius: 0
        ).cgPath
    }
}

/// 交互式右滑返回：驱动自定义转场的百分比进度（跟手、可取消）。
@MainActor
final class NavigationPopInteraction: UIPercentDrivenInteractiveTransition {
    weak var navigationController: UINavigationController?

    private(set) var isInteracting = false

    func handleGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard let view = gesture.view else { return }
        switch gesture.state {
        case .began:
            guard navigationController?.viewControllers.count ?? 0 > 1 else {
                isInteracting = false
                return
            }
            isInteracting = true
            navigationController?.popViewController(animated: true)
        case .changed:
            let translation = gesture.translation(in: view)
            let progress = min(1, max(0, translation.x / view.bounds.width))
            update(progress)
        case .ended, .cancelled, .failed:
            isInteracting = false
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            let shouldFinish = velocity.x > 600
                || translation.x / view.bounds.width > 0.4
            shouldFinish ? finish() : cancel()
        default:
            isInteracting = false
            cancel()
        }
    }
}
