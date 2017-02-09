//
//  UserQueryViewController.swift
//  Swift Chat Demo
//
//  Created by Ben Lei on 8/2/2017.
//  Copyright © 2017 Skygear. All rights reserved.
//

import Foundation
import SKYKitChat
import SVProgressHUD

let ShowDirectConversationSegueIdentifier: String = "ShowDirectConversation"

class UserQueryViewController: SKYChatParticipantListViewController {

    var selectedUserConversation: SKYUserConversation?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.queryMethod = .ByName
        self.delegate = self

        if let userID = self.skygear.currentUser?.userID {
            self.participantScope = SKYQuery(recordType: "user",
                                             predicate: NSPredicate(format: "_id != %@", userID))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.selectedUserConversation = nil
        self.searchBar?.resignFirstResponder()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {

        self.searchBar?.resignFirstResponder()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        guard let segueID = segue.identifier else {
            // cannot identify the segue
            return
        }

        switch segueID {
        case ShowDirectConversationSegueIdentifier:
            if let vc = segue.destination as? ConversationViewController {
                vc.userConversation = self.selectedUserConversation
            }
        default:
            break
        }
    }
}

extension UserQueryViewController: SKYChatParticipantListViewControllerDelegate {
    func listViewController(_ controller: SKYChatParticipantListViewController,
                            didSelectParticipant participant: SKYRecord)
    {
        var title: String? = nil
        if let name = participant.object(forKey: "name") as? CVarArg {
            title = String.localizedStringWithFormat("Chat with %@", name)
        }

        SVProgressHUD.show()
        self.skygear.chatExtension?.createDirectConversation(
            userID: participant.recordID.recordName,
            title: title,
            metadata: nil,
            completion: { (result, error) in
                SVProgressHUD.dismiss()

                guard error == nil else {
                    SVProgressHUD.showError(withStatus: error?.localizedDescription)
                    return
                }

                guard let userConv = result else {
                    SVProgressHUD.showError(withStatus: "Failed to create conversation")
                    return
                }

                self.selectedUserConversation = userConv
                self.performSegue(withIdentifier: ShowDirectConversationSegueIdentifier,
                                  sender: self)
            }
        )
    }

}
