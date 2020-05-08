//
// Copyright © 2020 Anonyome Labs, Inc. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import UIKit
import SudoVirtualCards
import SudoProfiles

// Reusable tableview cell

/// This View Controller presents a form so that a user can add a `Card`.
///
/// - Links From:
///     - `CardListViewController`: A user chooses the "Create" option from the naviationg bar of the table view.
/// - Links To:
///     - `CardListViewController`: If a user successfully creates a card, they will be returned to this form.
class CreateCardViewController: UIViewController,
    UITableViewDelegate,
    UITableViewDataSource,
    InputFormCellDelegate,
    ProvisionCardObservable,
    LearnMoreViewDelegate {

    // MARK: - Outlets

    /// Table view that lists the input field for the form.
    @IBOutlet var tableView: UITableView!

    /// Shows supplementary information to the input form, such as the chosen sudo, funding source, and learn more.
    @IBOutlet var tableFooterView: UIView!

    @IBOutlet var idStackView: UIStackView!

    @IBOutlet var learnMoreView: LearnMoreView!

    // MARK: Outlets: UILabel

    /// Label that shows the selected sudo identifier to create a `Card` against.
    @IBOutlet var sudoLabel: UILabel!

    /// Label that shows the first available `FundingSource` identifier that is used to fund the `Card`.
    @IBOutlet var fundingSourceLabel: UILabel!

    @IBOutlet var errorLabel: UILabel!

    // MARK: - Supplementary

    /// Typealias for a successful response call to `VirtualCardsClient.getFundingSourcesWithLimit(_:nextToken:cachePolicy:completion:)`.
    typealias FundingSourceListSuccessCompletion = ([FundingSource]) -> Void

    /// Typealias for a error response call to `VirtualCardsClient.getFundingSourcesWithLimit(_:nextToken:cachePolicy:completion:)`.
    typealias FundingSourceListErrorCompletion = (Error) -> Void

    /// Defaults used in `CreateCardViewController`.
    enum Defaults {
        /// Limit used when querying funding sources from `VirtualCardsClient`.
        static let fundingSourceLimit = 10
        /// Default currency ISO code that is supported when provisioning cards.
        static let provisionCurrency = "USD"
    }

    /// Segues that are performed in `CardListViewController`.
    enum Segue: String {
        /// Used to navigate to the `CardDetailViewController`.
        case navigateToCardDetail
        /// Used to navigate back to the `CardListViewController`.
        case returnToCardList
    }

    /// Input fields shown on the form.
    enum InputField: Int, CaseIterable {
        /// Name associated with the card to be created.
        case cardHolder
        /// Alias label for the cards.
        case cardLabel
        /// Address line 1 of the card.
        case addressLine1
        /// Address line 2 of the card.
        case addressLine2
        /// City of the card.
        case city
        /// State of the address of the card.
        case state
        /// Zip code of the address of the card.
        case zip
        /// Country of the address of the card.
        case country

        /// Returns true if the field is an optional input field.
        var isOptional: Bool {
            switch self {
            case .addressLine2:
                return true
            default:
                return false
            }
        }

        /// Label of the field shown to the user.
        var label: String {
            switch self {
            case .cardHolder:
                return "Card Holder"
            case .cardLabel:
                return "Card Label"
            case .addressLine1:
                return "Address Line 1"
            case .addressLine2:
                return "Address Line 2"
            case .city:
                return "City"
            case .state:
                return "State"
            case .zip:
                return "Zip"
            case .country:
                return "Country"
            }
        }

        /// Placeholder of the field.
        var placeholder: String {
            if isOptional {
                return "Enter \(label) (Optional)"
            } else {
                return "Enter \(label)"
            }
        }

        /// Default text populated for the field.
        ///
        /// Optional fields are not populated by default.
        var defaultText: String? {
            guard !isOptional else {
                return nil
            }
            switch self {
            case .cardHolder:
                return "Unlimited Cards"
            case .cardLabel:
                return "Shopping"
            case .addressLine1:
                return "123 Street Rd"
            case .city:
                return "Salt Lake City"
            case .state:
                return "UT"
            case .zip:
                return "84044"
            case .country:
                return "US"
            default:
                return nil
            }
        }
    }

    // MARK: - Properties

    /// `Sudo` that is associated with adding a card to.
    ///
    /// This is injected upon segue from `CardListViewController`.
    var sudo: Sudo = Sudo()

    /// Funding source to use to add a card.
    var fundingSource: FundingSource?

    /// The created card
    var card: Card?

    /// The frame of the visible keyboard. This will be updated alongside show/hide notifications.
    var keyboardFrame: CGRect = .zero

    // MARK: - Properties: Computed

    /// Virtual cards client used to get funding sources and add a card.
    var virtualCardsClient: SudoVirtualCardsClient {
        return AppDelegate.dependencies.virtualCardsClient
    }

    /// Array of input fields used on the view.
    let inputFields: [InputField] = InputField.allCases

    /// Inputted form data. Initialized with default data.
    var formData: [InputField: String] = {
        return InputField.allCases.reduce([:], { accumulator, field in
            var accumulator = accumulator
            accumulator[field] = field.defaultText
            return accumulator
        })
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationBar()
        configureTableView()
        configureFooterValues()
        configureLearnMoreView()
        setErrorLabelHidden(true)
        setCreateButtonEnabled(false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startListeningForKeyboardNotifications()
        loadFirstFundingSource()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopListeningForKeyboardNotifications()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Note: This ensures the table footer height matches the custom outlet assigned in the xib file
        tableView.tableFooterView?.frame.size.height = tableFooterView.frame.height
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let segueType = Segue.init(rawValue: segue.identifier ?? "")
        switch segueType {
        case .navigateToCardDetail:
            guard let cardDetail = segue.destination as? CardDetailViewController, let createdCard = self.card else {
                break
            }
            cardDetail.card = createdCard
        default:
            break
        }
    }

    // MARK: - Actions

    /// Action associated with tapping the "Create" button on the navigation item.
    ///
    /// This action will initiate the sequence of validating inputs and adding a card via the `virtualCardsClient`.
    @objc func didTapCreateCardButton() {
        createCard()
    }

    // MARK: - Operations

    /// Validates and creates a card based on the views form inputs.
    func createCard() {
        view.endEditing(true)
        guard validateFormData() else {
            presentErrorAlert(message: "Please ensure all fields are filled out")
            return
        }
        guard let fundingSource = fundingSource else {
            presentErrorAlert(message: "Internal error has occurred")
            return
        }
        guard let sudoId = sudo.id else {
            presentErrorAlert(message: "Sudo Id cannot be found")
            return
        }
        let billingAddressInput = Address(
            addressLine1: formData[.addressLine1] ?? "",
            addressLine2: formData[.addressLine2],
            city: formData[.city] ?? "",
            state: formData[.state] ?? "",
            postalCode: formData[.zip] ?? "",
            country: formData[.country] ?? ""
        )
        let input = ProvisionCardInput(
            sudoId: sudoId,
            fundingSourceId: fundingSource.id,
            cardHolder: formData[.cardHolder] ?? "",
            alias: formData[.cardLabel] ?? "",
            billingAddress: billingAddressInput,
            currency: Defaults.provisionCurrency
        )
        setCreateButtonEnabled(false)
        presentActivityAlert(message: "Creating Card")
        virtualCardsClient.provisionCardWithInput(
            input,
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case let .failure(error):
                        self?.setCreateButtonEnabled(true)
                        self?.dismissActivityAlert {
                            self?.presentErrorAlert(message: "Failed to create card", error: error)
                        }
                    default:
                        break
                    }
                }
            },
            observer: self
        )
    }

    /// List funding sources from the virtual cards service.
    ///
    /// - Parameters:
    ///   - cachePolicy: Cache policy used to retrieve the data.
    ///   - success: Closure called on a successful response.
    ///   - failure: Closure called on a failure response.
    func listFundingSource(
        cachePolicy: CachePolicy,
        success: @escaping FundingSourceListSuccessCompletion,
        failure: @escaping FundingSourceListErrorCompletion
    ) {
        virtualCardsClient.getFundingSourcesWithLimit(Defaults.fundingSourceLimit, nextToken: nil, cachePolicy: cachePolicy) { result in
            switch result {
            case let .success(output):
                success(output.items)
            case let .failure(error):
                failure(error)
            }
        }
    }

    // MARK: - Helpers: Configuration

    /// Configure the view's navigation bar.
    ///
    /// Sets the title of the navigation to "Create Card". Also sets the right bar to a create button, which will validate the form and attempt to create a
    /// card.
    func configureNavigationBar() {
        navigationItem.title = "Create Card"
        let createBarButton = UIBarButtonItem(title: "Create", style: .plain, target: self, action: #selector(didTapCreateCardButton))
        navigationItem.rightBarButtonItem = createBarButton
    }

    /// Configures the table view used to display the input form information.
    ///
    /// Registers the custom `InputFormTableViewCell` for use as the `"inputFormCell"` and also sets the table footer to the non-editable information.
    func configureTableView() {
        let inputFormTableViewCellNib = UINib(nibName: "InputFormTableViewCell", bundle: .main)
        tableView.register(inputFormTableViewCellNib, forCellReuseIdentifier: "inputFormCell")
        tableFooterView.backgroundColor = .none
        tableView.tableFooterView = UIView()
        tableView.tableFooterView?.addSubview(tableFooterView)
    }

    /// Configures the table footer values from the passed in `Sudo`.
    ///
    /// If a valid sudo is not found, an error will be presented to the suer, which results in a segue back to the `CardListViewController`.
    func configureFooterValues() {
        guard let sudoLabelText = sudo.label, !sudoLabelText.isEmpty else {
            presentErrorAlert(
                message: "An error has occurred: no sudo label found",
                okHandler: { _ in
                    self.performSegue(withIdentifier: Segue.navigateToCardDetail.rawValue, sender: self)
                }
            )
            return
        }
        guard let sudoId = sudo.id, !sudoId.isEmpty else {
            presentErrorAlert(
                message: "An error has occurred: no sudo id found",
                okHandler: { _ in
                    self.performSegue(withIdentifier: Segue.returnToCardList.rawValue, sender: self)
                }
            )
            return
        }
        sudoLabel.text = sudoLabelText
    }

    func configureLearnMoreView() {
        learnMoreView.label.text = "Virtual cards are the cornerstone of the Virtual Cards SDK. Virtual cards can be used as a proxy between a user's"
            + " personal funding source and online merchants."
        learnMoreView.delegate = self
    }

    // MARK: - Helpers

    /// Load the first funding source associated with the user's account.
    func loadFirstFundingSource() {
        listFundingSource(
            cachePolicy: .useOnline,
            success: { [weak self] fundingSources in
                DispatchQueue.main.async {
                    guard let weakSelf = self else { return }
                    if let fundingSource = fundingSources.first {
                        weakSelf.fundingSource = fundingSource
                        let fundingSourceText = "\(fundingSource.network.string) ****\(fundingSource.last4)"
                        weakSelf.fundingSourceLabel.text = fundingSourceText
                        weakSelf.setCreateButtonEnabled(true)
                    } else {
                        weakSelf.setErrorLabelHidden(false)
                        weakSelf.setCreateButtonEnabled(false)
                    }
                }
            }, failure: { [weak self] error in
                DispatchQueue.main.async {
                    self?.presentErrorAlert(message: "Failed to get funding sources", error: error)
                    self?.setCreateButtonEnabled(false)
                }
        })
    }

    /// Sets the Create Button in the navigation bar to enabled/disabled.
    ///
    /// - Parameter isEnabled: If true, the navigation Create button will be enabled.
    func setCreateButtonEnabled(_ isEnabled: Bool) {
        navigationItem.rightBarButtonItem?.isEnabled = isEnabled
    }

    func setErrorLabelHidden(_ isHidden: Bool) {
        errorLabel.isHidden = isHidden
        tableFooterView.layoutIfNeeded()
    }

    /// Validates the form data.
    /// - Returns: `true` if the form data is valid.
    func validateFormData() -> Bool {
        return inputFields.allSatisfy { fieldType in
            guard !fieldType.isOptional else {
                return true
            }
            guard let data = formData[fieldType] else {
                return false
            }
            return !data.isEmpty

        }
    }

    /// Get the form's input label for the current `indexPath`.
    func getInputLabel(forIndexPath indexPath: IndexPath) -> String {
        return InputField(rawValue: indexPath.row)?.label ?? "Field"
    }

    /// Get the form's input placeholder for the current `indexPath`.
    func getInputPlaceholder(forIndexPath indexPath: IndexPath) -> String {
        return InputField(rawValue: indexPath.row)?.placeholder ?? "Enter value"
    }

    /// Get the form's input text for the current `indexPath`.
    func getFormInput(forIndexPath indexPath: IndexPath) -> String? {
        guard let inputField = InputField(rawValue: indexPath.row) else {
            return nil
        }
        return formData[inputField]
    }

    // MARK: - Helpers: Keyboard

    func startListeningForKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    func stopListeningForKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc func keyboardDidShow(notification: Notification) {
        let keyboardRect = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        keyboardFrame = keyboardRect ?? .zero
        tableView.contentInset.bottom = (keyboardFrame.height + 12) // Height + some padding
    }

    @objc func keyboardWillHide() {
        keyboardFrame = .zero
        tableView.contentInset.bottom = 0
    }

    // MARK: - Conformance: UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return inputFields.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "inputFormCell") as? InputFormTableViewCell else {
            return InputFormTableViewCell()
        }
        cell.delegate = self
        cell.label.text = getInputLabel(forIndexPath: indexPath)
        cell.textField.placeholder = getInputPlaceholder(forIndexPath: indexPath)
        cell.textField.text = getFormInput(forIndexPath: indexPath)
        return cell
    }

    // MARK: - Conformance: UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? InputFormTableViewCell else {
            return
        }
        cell.textField.becomeFirstResponder()
    }

    // MARK: - Conformance: InputFormCellDelegate

    func inputCell(_ cell: InputFormTableViewCell, didUpdateInput input: String?) {
        guard let indexPath = tableView.indexPath(for: cell), let field = InputField(rawValue: indexPath.row) else {
            return
        }
        guard let input = cell.textField.text, !input.isEmpty else {
            formData[field] = nil
            return
        }
        formData[field] = input
    }

    // MARK: - Conformance: ProvisionCardObservable

    func provisioningStateDidChange(_ state: ProvisionalCard.State, card: Card?) {
        DispatchQueue.main.async {
            switch state {
            case .completed:
                self.setCreateButtonEnabled(true)
                self.dismissActivityAlert {
                    self.card = card
                    self.performSegue(
                        withIdentifier: Segue.navigateToCardDetail.rawValue,
                        sender: self)
                }
            case .failed:
                self.setCreateButtonEnabled(true)
                self.dismissActivityAlert {
                    self.presentErrorAlert(message: "Failed to create card")
                }
            default:
                break
            }
        }
    }

    func errorOccurred(_ error: Error) {
        DispatchQueue.main.async {
            self.setCreateButtonEnabled(true)
            self.dismissActivityAlert {
                self.presentErrorAlert(message: "Failed to create card", error: error)
            }
        }
    }

    // MARK: - Conformance: LearnMoreDelegate

    func didTapLearnMoreButton() {
        guard let docURL = URL(string: "https://docs.sudoplatform.com/guides/virtual-cards/manage-virtual-cards#creating-a-virtual-card") else {
            return
        }
        UIApplication.shared.open(docURL, options: [:], completionHandler: nil)
    }

}