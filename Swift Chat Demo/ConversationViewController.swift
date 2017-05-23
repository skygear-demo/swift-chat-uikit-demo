//
//  ConversationViewController.swift
//  Swift Chat Demo
//
//  Created by Ben Lei on 9/2/2017.
//  Copyright © 2017 Skygear. All rights reserved.
//

import SKYKitChat
import SVProgressHUD

let ShowConversationDetailSegueIdentifier: String = "ShowConversationDetail"

class ConversationViewController: SKYChatConversationViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self

        self.navigationItem.rightBarButtonItem =
            UIBarButtonItem(title: NSLocalizedString("Details", comment: ""),
                            style: .plain,
                            target: self,
                            action: #selector(conversationDetailsButtonDidTap(_:)))
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        guard let segueID = segue.identifier else {
            // cannot identify the segue
            return
        }

        switch segueID {
        case ShowConversationDetailSegueIdentifier:
            if let vc = segue.destination as? ConversationDetailViewController {
                vc.conversation = self.conversation
                vc.delegate = self
                vc.allowEditing =
                    self.conversation!.adminIds.contains(self.skygear.currentUserRecordID)
                vc.allowAddingParticipants = !(self.conversation!.isDistinctByParticipants)
            }
        default:
            break
        }
    }
}

// MARK: - Actions

extension ConversationViewController {
    func conversationDetailsButtonDidTap(_ button: UIBarButtonItem) {
        self.performSegue(withIdentifier: ShowConversationDetailSegueIdentifier, sender: self)
    }
}

// MARK: - SKYChatConversationViewControllerDelegate

extension ConversationViewController: SKYChatConversationViewControllerDelegate {
    func conversationViewController(_ controller: SKYChatConversationViewController,
                                    didFetchedParticipants participants: [SKYRecord]) {

        ChatHelper.shared.cacheUserRecords(participants)
    }
    
    func conversationViewController(_ controller: SKYChatConversationViewController, didFetchedMessages messages: [SKYMessage]) {
        SVProgressHUD.dismiss()
    }
    
    func startFetchingMessages(_ controller: SKYChatConversationViewController) {
        SVProgressHUD.show()
    }

}

extension ConversationViewController: ConversationDetailViewControllerDelegate {
    func conversationDetailViewController(
        didFinish viewController: ConversationDetailViewController) {

        guard let nc = self.navigationController else {
            return
        }

        guard let detailsVC = nc.topViewController as? ConversationDetailViewController else {
            return
        }

        nc.popViewController(animated: true)

        if detailsVC.edited {
            // update the conversation

            self.conversation?.title = detailsVC.conversationTitle
            self.conversation?.adminIds = detailsVC.adminIDs
            self.conversation?.participantIds = detailsVC.participantIDs

            SVProgressHUD.showInfo(
                withStatus: NSLocalizedString("Updating conversation...",
                                              comment: "")
            )
            self.skygear.chatExtension?.saveConversation(
                self.conversation!, completion: { (result, err) in
                    SVProgressHUD.dismiss()

                    guard err == nil else {
                        SVProgressHUD.showError(withStatus: err!.localizedDescription)
                        return
                    }

                    guard let conv = result else {
                        SVProgressHUD.showError(
                            withStatus: NSLocalizedString("Failed to update conversation",
                                                          comment: "")
                        )

                        return
                    }

                    self.conversation = conv
                }
            )

        }
    }
}
