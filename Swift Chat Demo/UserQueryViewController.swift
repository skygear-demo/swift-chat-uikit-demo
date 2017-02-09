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

class UserQueryViewController: SKYChatParticipantListViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        self.queryMethod = .ByName
        self.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.searchBar?.resignFirstResponder()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {

        self.searchBar?.resignFirstResponder()
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

                // TODO: link to conversation view
                print("Conversation \(userConv.conversation.recordID.recordName!) is created")
            }
        )
    }

}
