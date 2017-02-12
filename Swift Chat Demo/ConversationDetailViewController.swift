//
//  ConversationDetailViewController.swift
//  Swift Chat Demo
//
//  Created by atwork on 2/12/2016.
//  Copyright © 2016 Skygear. All rights reserved.
//

import UIKit
import SKYKit
import SKYKitChat
import SVProgressHUD

@objc protocol ConversationDetailViewControllerDelegate {
    @objc optional func conversationDetailViewController(
        didCancel viewController: ConversationDetailViewController)

    @objc optional func conversationDetailViewController(
        didFinish viewController: ConversationDetailViewController)
}

class ConversationDetailViewController: UITableViewController {

    enum TableViewSection {
        case Title
        case Participant
        case LeaveConversation
    }

    enum TableViewCell: String {
        case EditTitle = "edit_title"
        case Participant = "participant"
        case LeaveConversation = "leave_conversation"
        case Plain = "plain"

        var identifier: String {
            return self.rawValue
        }
    }

    var conversationTitle: String?
    var participantIDs: [String] = []
    var adminIDs: [String] = []
    var allowEditing: Bool = true
    var allowAddingParticipants: Bool = true
    var allowLeaving: Bool = true
    var showCancelButton: Bool = false
    var delegate: ConversationDetailViewControllerDelegate?

    var edited: Bool = false {
        didSet {
            self.navigationItem.rightBarButtonItem?.isEnabled = self.edited
        }
    }
    var conversation: SKYConversation? {
        didSet {
            if let conv = self.conversation {
                self.conversationTitle = conv.title
                self.participantIDs = conv.participantIds
                self.adminIDs = conv.adminIds
            }
        }
    }

    var sections: [TableViewSection] = []
}

// MARK: - Lifecycles

extension ConversationDetailViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        self.sections = [.Title, .Participant]
        if allowLeaving {
            self.sections.append(.LeaveConversation)
        }

        if showCancelButton {
            self.navigationItem.leftBarButtonItem =
                UIBarButtonItem(title: "Cancel",
                                style: .plain,
                                target: self,
                                action: #selector(cancelButtonDidTap(_:)))
        }

        let doneButton = UIBarButtonItem(title: "Done",
                                         style: .done,
                                         target: self,
                                         action: #selector(doneButtonDidTap(_:)))
        doneButton.isEnabled = false
        self.navigationItem.rightBarButtonItem = doneButton
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

// MARK: - Rendering

extension ConversationDetailViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionID = self.sections[section]
        switch sectionID {
        case .Title:
            return 1
        case .Participant:
            var cellCount = self.participantIDs.count
            if self.allowEditing && self.allowAddingParticipants {
                cellCount += 1
            }

            return cellCount
        case .LeaveConversation:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionID = self.sections[indexPath.section]

        switch sectionID {
        case .Title:
            return self.allowEditing ?
                self.tableView(tableView, editableTitleSectionCellForRowAt: indexPath):
                self.tableView(tableView, titleSectionCellForRowAt: indexPath)
        case .Participant:
            return self.tableView(tableView, participantSectionCellForRowAt: indexPath)
        case .LeaveConversation:
            return self.tableView(tableView, leaveConversationSectionCellForRowAt: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, titleSectionCellForRowAt indexPath: IndexPath)
        -> UITableViewCell {

            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: TableViewCell.Plain.identifier) else {

                    return UITableViewCell(style: .default, reuseIdentifier: nil)
            }

            if self.conversation!.title != nil && self.conversation!.title!.characters.count > 0 {
                cell.textLabel?.text = self.conversation!.title
                cell.textLabel?.textColor = self.view.tintColor
            } else {
                cell.textLabel?.text = NSLocalizedString("Untitled Conversation", comment: "")
                cell.textLabel?.textColor = UIColor.lightGray
            }

            return cell
    }

    func tableView(_ tableView: UITableView, editableTitleSectionCellForRowAt indexPath: IndexPath)
        -> UITableViewCell {

            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: TableViewCell.EditTitle.identifier) as?
                ConversationDetailsEditTitleTableViewCell else {

                    return UITableViewCell(style: .default, reuseIdentifier: nil)
            }

            cell.titleTextField.text = self.conversationTitle
            cell.titleTextField.delegate = self

            return cell
    }

    func tableView(_ tableView: UITableView, participantSectionCellForRowAt indexPath: IndexPath)
        -> UITableViewCell {

            guard indexPath.row < self.participantIDs.count else {

                // Add participant cell
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: TableViewCell.Plain.identifier) ??
                    UITableViewCell(style: .default, reuseIdentifier: nil)

                cell.textLabel?.text = NSLocalizedString("Add New", comment: "")

                return cell
            }

            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: TableViewCell.Participant.identifier) else {

                    return UITableViewCell(style: .default, reuseIdentifier: nil)
            }

            let participantID = self.participantIDs[indexPath.row]

            cell.textLabel?.text =
                ChatHelper.shared.userRecord(userID: participantID)?.chat_versatileNameOfUserRecord
            cell.detailTextLabel?.text = self.adminIDs.contains(participantID) ? "Admin" : ""

            return cell
    }

    func tableView(_ tableView: UITableView,
                   leaveConversationSectionCellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: TableViewCell.LeaveConversation.identifier) else {

                return UITableViewCell(style: .default, reuseIdentifier: nil)
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let sectionID = self.sections[section]

        switch sectionID {
        case .Participant:
            return NSLocalizedString("Participants", comment: "")
        default:
            return ""
        }
    }

    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let sectionID = self.sections[indexPath.section]

        switch sectionID {
        case .Participant:
            guard indexPath.row < self.participantIDs.count else {
                // Add participant cell
                return false
            }

            let participantID = self.participantIDs[indexPath.row]
            let isDistinctByParticipants = self.conversation?.isDistinctByParticipants ?? false
            return (self.allowEditing &&
                    !isDistinctByParticipants &&
                    participantID != SKYContainer.default().currentUserRecordID!)
        default:
            return false
        }
    }

    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCellEditingStyle,
                            forRowAt indexPath: IndexPath) {

        if editingStyle == .delete {
            let removedID = self.participantIDs.remove(at: indexPath.row)
            if let adminIndex = self.adminIDs.index(of: removedID) {
                self.adminIDs.remove(at: adminIndex)
            }

            self.tableView.deleteRows(at: [indexPath], with: .fade)
            self.edited = true
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let sectionID = self.sections[indexPath.section]

        switch sectionID {
        case .Participant:
            if indexPath.row == self.participantIDs.count {
                // Add participant cell
                let vc = SKYChatParticipantListViewController.create()
                vc.queryMethod = .ByName
                vc.delegate = self

                self.present(vc, animated: true, completion: nil)
            }
        case .LeaveConversation:
            self.leaveConversation()
        default:
            break
        }
    }
}

// MARK: - Actions

extension ConversationDetailViewController {

    func cancelButtonDidTap(_ sender: Any) {
        self.delegate?.conversationDetailViewController?(didCancel: self)
    }

    func doneButtonDidTap(_ sender: Any) {
        self.delegate?.conversationDetailViewController?(didFinish: self)
    }
}

// MARK: - SKYChatParticipantListViewControllerDelegate

extension ConversationDetailViewController: SKYChatParticipantListViewControllerDelegate {

    func listViewController(_ controller: SKYChatParticipantListViewController,
                            didSelectParticipant participant: SKYRecord) {

        self.dismiss(animated: true, completion: nil)
        ChatHelper.shared.cacheUserRecord(participant)

        if let participantID = participant.recordID.recordName {
            var participantSet = Set(self.participantIDs)
            let (inserted, _) = participantSet.insert(participantID)

            if inserted {
                self.participantIDs = Array(participantSet)
                self.edited = true

                self.tableView.reloadData()
            }
        }
    }
}

// MARK: - UITextFieldDelegate

extension ConversationDetailViewController: UITextFieldDelegate {

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        if let text = textField.text as? NSString {
            self.conversationTitle = text.replacingCharacters(in: range, with: string)
        }

        self.edited = true
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        self.conversationTitle = textField.text
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
}

// MARK: - Utils

extension ConversationDetailViewController {

    func leaveConversation() {
        let alert = UIAlertController(
            title: NSLocalizedString("Leave Conversation", comment: ""),
            message: NSLocalizedString("This will remove yourselves from this conversation",
                                       comment: ""),
            preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Leave", comment: ""),
            style: .destructive,
            handler: { _ in self.confirmLeaveConversation() })
        )

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
                                      style: .cancel,
                                      handler: nil))

        self.present(alert, animated: true, completion: nil)
    }

    func confirmLeaveConversation() {
        SVProgressHUD.show()
        SKYContainer.default().chatExtension?.leave(
            self.conversation!,
            completion: { (err) in
                guard err == nil else {
                    let alert = UIAlertController(
                        title: NSLocalizedString("Unable to Leave Conversation", comment: ""),
                        message: err?.localizedDescription,
                        preferredStyle: .alert)

                    alert.addAction(UIAlertAction(
                        title: NSLocalizedString("OK", comment: ""),
                        style: .default,
                        handler: nil))

                    self.present(alert, animated: true, completion: nil)
                    return
                }

                let _ = self.navigationController?.popToRootViewController(animated: true)
        }
        )
    }
}
