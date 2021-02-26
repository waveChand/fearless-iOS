import Foundation
import CommonWallet
import BigInt

final class StakingAmountPresenter {
    weak var view: StakingAmountViewProtocol?
    var wireframe: StakingAmountWireframeProtocol!
    var interactor: StakingAmountInteractorInputProtocol!

    let balanceViewModelFactory: BalanceViewModelFactoryProtocol
    let rewardDestViewModelFactory: RewardDestinationViewModelFactoryProtocol
    let selectedAccount: AccountItem
    let logger: LoggerProtocol
    let feeDebounce: TimeInterval
    let applicationConfig: ApplicationConfigProtocol

    private var priceData: PriceData?
    private var balance: Decimal?
    private var fee: Decimal?
    private var loadingFee: Bool = false
    private var asset: WalletAsset
    private var amount: Decimal?
    private var rewardDestination: RewardDestination = .restake
    private var payoutAccount: AccountItem
    private var loadingPayouts: Bool = false

    private lazy var scheduler: SchedulerProtocol = Scheduler(with: self, callbackQueue: .main)

    private var calculatedReward = CalculatedReward(restakeReturn: 4.12,
                                                    restakeReturnPercentage: 0.3551,
                                                    payoutReturn: 2.15,
                                                    payoutReturnPercentage: 0.2131)

    deinit {
        scheduler.cancel()
    }

    init(asset: WalletAsset,
         selectedAccount: AccountItem,
         rewardDestViewModelFactory: RewardDestinationViewModelFactoryProtocol,
         balanceViewModelFactory: BalanceViewModelFactoryProtocol,
         feeDebounce: TimeInterval = 2.0,
         applicationConfig: ApplicationConfigProtocol,
         logger: LoggerProtocol) {
        self.asset = asset
        self.selectedAccount = selectedAccount
        self.payoutAccount = selectedAccount
        self.rewardDestViewModelFactory = rewardDestViewModelFactory
        self.balanceViewModelFactory = balanceViewModelFactory
        self.feeDebounce = feeDebounce
        self.applicationConfig = applicationConfig
        self.logger = logger
    }

    private func provideRewardDestination() {
        do {
            switch rewardDestination {
            case .restake:
                let viewModel = try rewardDestViewModelFactory.createRestake(from: calculatedReward)
                view?.didReceiveRewardDestination(viewModel: viewModel)
            case .payout:
                let viewModel = try rewardDestViewModelFactory
                    .createPayout(from: calculatedReward, account: payoutAccount)
                view?.didReceiveRewardDestination(viewModel: viewModel)
            }
        } catch {
            logger.error("Can't create reward destination")
        }
    }

    private func provideAsset() {
        let viewModel = balanceViewModelFactory.createAssetBalanceViewModel(amount ?? 0.0,
                                                                            balance: balance,
                                                                            priceData: priceData)
        view?.didReceiveAsset(viewModel: viewModel)
    }

    private func provideFee() {
        if let fee = fee {
            let feeViewModel = balanceViewModelFactory.balanceFromPrice(fee, priceData: priceData)
            view?.didReceiveFee(viewModel: feeViewModel)
        } else {
            view?.didReceiveFee(viewModel: nil)
        }
    }

    private func provideAmountInputViewModel() {
        let viewModel = balanceViewModelFactory.createBalanceInputViewModel(amount)
        view?.didReceiveInput(viewModel: viewModel)
    }

    private func scheduleFeeEstimation() {
        scheduler.cancel()

        if !loadingFee {
            loadingFee = true
            estimateFee()
        } else {
            scheduler.notifyAfter(feeDebounce)
        }
    }

    private func estimateFee() {
        if let amount = (amount ?? 0.0).toSubstrateAmount(precision: asset.precision) {
            loadingFee = true
            interactor.estimateFee(for: selectedAccount.address,
                                   amount: amount,
                                   rewardDestination: rewardDestination)
        }
    }
}

extension StakingAmountPresenter: StakingAmountPresenterProtocol {
    func setup() {
        provideAmountInputViewModel()
        provideRewardDestination()

        interactor.setup()

        estimateFee()
    }

    func selectRestakeDestination() {
        rewardDestination = .restake
        provideRewardDestination()

        scheduleFeeEstimation()
    }

    func selectPayoutDestination() {
        rewardDestination = .payout(address: payoutAccount.address)
        provideRewardDestination()

        scheduleFeeEstimation()
    }

    func selectAmountPercentage(_ percentage: Float) {
        if let balance = balance, let fee = fee {
            let newAmount = max(balance - fee, 0.0) * Decimal(Double(percentage))

            if newAmount > 0 {
                amount = newAmount

                provideAmountInputViewModel()
                provideAsset()
            } else {
                wireframe.presentNotEnoughFunds(from: view)
            }
        }
    }

    func selectPayoutAccount() {
        guard !loadingPayouts else {
            return
        }

        loadingPayouts = true

        interactor.fetchAccounts()
    }

    func selectLearnMore() {
        if let view = view {
            wireframe.showWeb(url: applicationConfig.learnPayoutURL,
                              from: view,
                              style: .automatic)
        }
    }

    func updateAmount(_ newValue: Decimal) {
        amount = newValue

        provideAsset()
        scheduleFeeEstimation()
    }

    func proceed() {
        guard let amount = amount, let fee = fee, let balance = balance else {
            return
        }

        guard amount + fee <= balance else {
            wireframe.presentNotEnoughFunds(from: view)
            return
        }

        let stakingState = StartStakingResult(amount: amount,
                                              rewardDestination: rewardDestination,
                                              fee: fee)

        wireframe.proceed(from: view, result: stakingState)
    }

    func close() {
        wireframe.close(view: view)
    }
}

extension StakingAmountPresenter: SchedulerDelegate {
    func didTrigger(scheduler: SchedulerProtocol) {
        estimateFee()
    }
}

extension StakingAmountPresenter: StakingAmountInteractorOutputProtocol {
    func didReceive(accounts: [AccountItem]) {
        loadingPayouts = false

        let context = PrimitiveContextWrapper(value: accounts)

        wireframe.presentAccountSelection(accounts,
                                          selectedAccountItem: payoutAccount,
                                          delegate: self,
                                          from: view,
                                          context: context)
    }

    func didReceive(price: PriceData?) {
        self.priceData = price
        provideAsset()
        provideFee()
    }

    func didReceive(balance: DyAccountData?) {
        if let availableValue = balance?.available {
            self.balance = Decimal.fromSubstrateAmount(availableValue,
                                                       precision: asset.precision)
        } else {
            self.balance = 0.0
        }

        provideAsset()
    }

    func didReceive(paymentInfo: RuntimeDispatchInfo,
                    for amount: BigUInt,
                    rewardDestination: RewardDestination) {
        loadingFee = false

        if let feeValue = BigUInt(paymentInfo.fee),
           let fee = Decimal.fromSubstrateAmount(feeValue, precision: asset.precision) {
            self.fee = fee
        } else {
            self.fee = nil
        }

        provideFee()
    }

    func didReceive(error: Error) {
        loadingPayouts = false
        loadingFee = false

        let locale = view?.localizationManager?.selectedLocale

        if !wireframe.present(error: error, from: view, locale: locale) {
            logger.error("Did receive error: \(error)")
        }
    }
}

extension StakingAmountPresenter: ModalPickerViewControllerDelegate {
    func modalPickerDidSelectModelAtIndex(_ index: Int, context: AnyObject?) {
        guard
            let accounts =
            (context as? PrimitiveContextWrapper<[AccountItem]>)?.value else {
            return
        }

        payoutAccount = accounts[index]
        provideRewardDestination()
    }
}
