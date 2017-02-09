//
//  ConversationViewController.swift
//  Swift Chat Demo
//
//  Created by Ben Lei on 9/2/2017.
//  Copyright © 2017 Skygear. All rights reserved.
//

import SKYKitChat

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
                vc.adminIDs = self.conversation!.adminIds
                vc.participantIDs = self.conversation!.participantIds
                vc.conversationID = self.conversation!.recordID.recordName
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
}
