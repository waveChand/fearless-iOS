import UIKit

class PinSetupWireframe: PinSetupWireframeProtocol {
    lazy var rootAnimator: RootControllerAnimationCoordinatorProtocol = RootControllerAnimationCoordinator()

    func showMain(from view: PinSetupViewProtocol?) {
        guard let mainViewController = MainTabBarViewFactory.createView()?.controller else {
            return
        }

        rootAnimator.animateTransition(to: mainViewController)
    }

    func showSignup(from view: PinSetupViewProtocol?) {
        guard let signupViewController = OnboardingMainViewFactory.createViewForOnboarding()?.controller else {
            return
        }

        rootAnimator.animateTransition(to: signupViewController)
    }
}
