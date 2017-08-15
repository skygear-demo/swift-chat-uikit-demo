//
//  ConversationListViewController.swift
//  Swift Chat Demo
//
//  Created by Ben Lei on 9/2/2017.
//  Copyright © 2017 Skygear. All rights reserved.
//

import SKYKitChat
import SVProgressHUD

let ShowGroupConversationSegueIdentifier: String = "ShowGroupConversation"
let ShowCreateConversationSegueIdentifier: String = "ShowCreateConversation"

class ConversationListViewController: SKYChatConversationListViewController {

    var selectedConversation: SKYConversation?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(createConversationButtonDidTap(_:)))
        NotificationCenter.default.addObserver(forName: NSNotification.Name.SKYContainerDidChangeCurrentUser,
                                               object: nil,
                                               queue: OperationQueue.main) { (_) in
                                                self.performQuery(callback: nil)
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        guard let segueID = segue.identifier else {
            // cannot identify the segue
            return
        }

        switch segueID {
        case ShowGroupConversationSegueIdentifier:
            if let vc = segue.destination as? ConversationViewController {
                vc.conversation = self.selectedConversation
            }
        case ShowCreateConversationSegueIdentifier:
            if let nc = segue.destination as? UINavigationController,
                let vc = nc.viewControllers.first as? ConversationDetailViewController {

                vc.title = NSLocalizedString("Create Conversation", comment: "")
                vc.participantIDs = [self.skygear.auth.currentUserRecordID!]
                vc.adminIDs = [self.skygear.auth.currentUserRecordID!]
                vc.allowLeaving = false
                vc.showCancelButton = true
                vc.delegate = self
            }
        default:
            break
        }
    }
}

// MARK: - Actions

extension ConversationListViewController {

    func createConversationButtonDidTap(_ button: UIBarButtonItem) {
        self.performSegue(withIdentifier: ShowCreateConversationSegueIdentifier, sender: self)
    }
}

// MARK: - SKYChatConversationListViewControllerDelegate

extension ConversationListViewController: SKYChatConversationListViewControllerDelegate {

    func listViewController(_ controller: SKYChatConversationListViewController,
                            didSelectConversation conversation: SKYConversation) {
        self.selectedConversation = conversation
        self.performSegue(withIdentifier: ShowGroupConversationSegueIdentifier,
                          sender: self)
    }
}

// MARK: - ConversationDetailViewControllerDelegate

extension ConversationListViewController: ConversationDetailViewControllerDelegate {

    func conversationDetailViewController(didCancel viewController: ConversationDetailViewController) {
        self.dismiss(animated: true, completion: nil)
    }

    func conversationDetailViewController(didFinish viewController: ConversationDetailViewController) {
        self.dismiss(animated: true, completion: nil)

        let conversationTitle = viewController.conversationTitle
        let participantIDs = viewController.participantIDs
        let adminIDs = viewController.adminIDs

        SVProgressHUD.show()
        self.skygear.chatExtension?.createConversation(
            participantIDs: participantIDs,
            title: conversationTitle,
            metadata: nil,
            adminIDs: adminIDs,
            distinctByParticipants: false,
            completion: { (result, error) in
                SVProgressHUD.dismiss()

                guard error == nil else {
                    SVProgressHUD.showError(withStatus: error?.localizedDescription)
                    return
                }

                guard let conversation = result else {
                    SVProgressHUD.showError(withStatus: "Failed to create conversation")
                    return
                }

                self.selectedConversation = conversation
                self.performSegue(withIdentifier: ShowGroupConversationSegueIdentifier,
                                  sender: self)
                self.performQuery(callback: nil);
        }
    )
    }
}
