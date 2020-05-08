//
// Copyright © 2020 Anonyome Labs, Inc. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import UIKit
import SudoUser
import SudoProfiles

/// This View Controller presents a form so that a user can create a `Sudo`.
///
/// - Links From:
///     - `SudoListViewController`: A user chooses the "Create" option from the top right corner of the navigation bar.
/// - Links To:
///     - `SudoListViewController`: If a user successfully creates a Sudo, they will be returned to this form.
class CreateSudoViewController: UIViewController, LearnMoreViewDelegate {

    // MARK: - Outlets

    /// Label that provides some instruction for the Sudo label.
    @IBOutlet weak var labelTextField: UITextField!

    /// View appearing at the end of the content providing informative text.
    @IBOutlet var learnMoreView: LearnMoreView!

    // MARK: - Supplementary

    /// Segues that are performed in `SudoListViewController`.
    enum Segue: String {
        /// Navigate to the `CardListViewController`.
        case navigateToCardList
    }

    // MARK: - Properties: Computed

    /// Sudo profiles client used to perform get and create Sudos.
    var profilesClient: SudoProfilesClient {
        return AppDelegate.dependencies.profilesClient
    }

    /// The created Sudo
    private var sudo: Sudo?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationBar()
        configureLearnMoreView()
        createButtonShouldBeEnabled(self.labelTextField)
        labelTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let segueType = Segue(rawValue: segue.identifier ?? "")
        switch segueType {
        case .navigateToCardList:
            guard let cardList = segue.destination as? CardListViewController, let createdSudo = self.sudo else {
                break
            }
            cardList.sudo = createdSudo
        default:
            break
        }
    }

    // MARK: - Actions

    /// Action associated with providing input to the text field.
    ///
    /// This action will enable the "Create" button on the navigation bar.
    @objc func textFieldDidChange(_ textField: UITextField) {
        // enable create button when textfield is not empty
        createButtonShouldBeEnabled(textField)
    }

    /// Action associated with tapping the "Create" button on the navigation bar.
    ///
    /// This action will initiate the sequence of  creating a Sudo via the `profilesClient`.
    @objc func didTapCreateSudoButton() {
        createSudo()
    }

    // MARK: - Operations

    /// Creates a Sudo based on the view's form inputs.
    func createSudo() {
        let sudo = Sudo(title: nil, firstName: nil, lastName: nil, label: labelTextField.text, notes: nil, avatar: nil)
        presentActivityAlert(message: "Creating sudo")
        do {
            try profilesClient.createSudo(sudo: sudo) { result in
                DispatchQueue.main.async {
                    // dismiss activity alert
                    self.dismissActivityAlert {
                        switch result {
                        case .success(let createdSudo):
                            self.sudo = createdSudo
                            self.performSegue(
                                withIdentifier: Segue.navigateToCardList.rawValue,
                                sender: self)
                        case .failure(let error):
                            self.presentErrorAlert(message: "Failed to create sudo", error: error)
                        }
                    }
                }
            }
        } catch let error {
            dismiss(animated: true) {
                self.presentErrorAlert(message: "Failed to create sudo", error: error)
            }
        }
    }

    // MARK: - Helpers: Configuration

    /// Configure the view's navigation bar.
    ///
    /// Sets the title of the navigation to "Create Sudo" and sets the right bar to a create button, which will validate the form
    /// and attempt to create a Sudo.
    func configureNavigationBar() {
        let createBarButton = UIBarButtonItem(title: "Create", style: .plain, target: self, action: #selector(didTapCreateSudoButton))
        navigationItem.rightBarButtonItem = createBarButton
    }

    /// Configure the view's "Learn more" view.
    ///
    /// Sets an informative text label and "Learn more" button which when tapped will redirect the user to a Sudo Platform webpage.
    func configureLearnMoreView() {
        learnMoreView.delegate = self
        learnMoreView.label.text = "Virtual cards must belong to a Sudo. A Sudo is a digital identity created and owned by a real person."
    }

    // MARK: - Helpers

    /// Sets the create button in the navigation bar to enabled/disabled.
    func createButtonShouldBeEnabled(_ textField: UITextField) {
        let isEnabled = !(textField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        navigationItem.rightBarButtonItem?.isEnabled = isEnabled
    }

    // MARK: - Conformance: LearnMoreViewDelegate

    func didTapLearnMoreButton() {
        guard let docURL = URL(string: "https://docs.sudoplatform.com/guides/sudos") else {
            return
        }
        UIApplication.shared.open(docURL, options: [:], completionHandler: nil)
    }
}
