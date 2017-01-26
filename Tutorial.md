# Skygear Swift Chat Tutorial
This is a tutorial for intermediate iOS developer for adopting the Skygear Chat extention. The tutorial focuses on how to implement the core function of a Chat app with Skygear `SKYKit` and `SKYChatKit`.

The use of this tutorial:
- We have commented all the Skygear related code and marked the number in the code. Please clone the whole project and follow the numbers to understand the `SKYKit` and `SKYChatKit`. 
- To start with, please clone the project from [here](https://github.com/skygear-demo/swift-chat-demo/tutorial)
- The convered feature in this tutorial includes:
    - [Configuration of Skygear](#part-1-configuration-of-skygear)
    - [Basic Usage of `SKYKit` & `SKYChatKit`](#part-2-basic-usage-of-skykit-and-skychatkit)
    - [Find Users](#part-3-find-users)
    - [Send Message](#part-4-send-message)
    - [Create Direct Chat / Group Chat](#part-5-create-direct-chat-or-group-chat)
    - [Leave a conversation](#part-6-leave-a-conversation)
    - [Trigger Typing Event](#part-7-trigger-a-typing-event)
    - [Subscription To New Message](#part-8-subscribe-to-new-message)
    - [Subscription To Typing Indicator](#part-9-subscribe-to-typing-indicator)
    - [Fetch Conversations](#part-10-fetch-conversations)
    - [Participants of conversation](#part-11-participants-of-conversation)
    - [Unread Count](#part-12-unread-count)
    - [Chat History](#part-13-chat-history)
    - [Notification](#part-14-notification)
- We have a complete tutorial for beginner to create the chat app from zero [here]().

## Part 1 - Configuration of Skygear
1. Register an account on [Skygear](skygear.io) to get the server endpoint and API Key. You can get the information in the "INFO" section in the portal.

    ![](https://i.imgur.com/kja9Z3W.png) 

2. Turn on the Chat plugin in "PLUG-INS" section.
    ![](https://i.imgur.com/K77D6R7.png)

3. Configure the Server endpoint and API Key in `AppDelegate.swift`. (Indicated as Part 1.3 in the code)

    Part 1.3 (In `AppDelegate.swift`)
    ```swift
    SKYContainer.default().configAddress("<your server endpoint>")
    SKYContainer.default().configure(withAPIKey: "<your api key>")
    ```

## Part 2 - Basic Usage of `SKYKit` and `SKYChatKit`
1. When you are using the methods related to the Cloud Database (e.g. CRUD of records, login or logout), `SKYContainer.default()` is commonly used. Therefore, you may declare the variable at the beginning and use that easier in your class.

    ```swift
    var container = SKYContainer.default()!
    ```
2. For the `SKYChatKit`, we need to use `SKYContainer.default().chatExtension`. Therefore, you can also decalre the vairable at the beginner. 

    ```swift
    var chat: SKYChatExtension = SKYContainer.default().chatExtension!
    ```
3. The ID of the current user can be retrieve by:
    ```swift
     SKYContainer.default().currentUserRecordID
     ```
    
When you see `container` or `chat` later in this tutorial, if not specify, they are both regarding to the variable decalration on the above.

## Part 3 - Find Users
The user record can be found by querying the `SKYContainer`. By the method `queryUsers(byUsernames: [String]!, completionHandler: (([SKYRecord]?, Error?) -> Void)!)` provided in the `SKYContainer`, we can get the `SKYRecord` of the provided usernames.

Part 3.1 (In `SearchUserHelper.swift`)
```swift
container.queryUsers(byUsernames: [username]) { (records, err) in
    if let error = err {
        let alert = UIAlertController(title: "Cannot Find User", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
        completion?(nil)
        return
    }
    
    // Get the first result in the query as the found user
    guard let foundUser = records?.first else {
        hud.label.text = "User Not Found"
        hud.mode = .text
        hud.hide(animated: true, afterDelay: 1.0)
        completion?(nil)
        return
    }

    hud.hide(animated: true)
    ChatHelper.shared.cacheUserRecord(foundUser)
    completion?(foundUser)
}
```


## Part 4 - Send Message
The codes related to send messge in the demo app are mainly in `MessagesViewController.swift`.

We can use `addMessage(message: SKYMessage, to: SKYConversation, completion:  SKYChatMessageCompletion?)` to send out the message to the Cloud Database. Documentation [here](http://cocoadocs.org/docsets/SKYKitChat/0.0.1/Classes/SKYChatExtension.html#//api/name/addMessage:toConversation:completion:NS_SWIFT_NAME:).

`SKYMessage`: The message object in `SKYChatKit`. With the follow attributes:
- conversationID (`SKYRecordID`)
- body (`String`)
- metadata (`NSDictionary`)
- attachment (`SKYAsset`)
- syncingToServer (`bool`)
- alreadySyncToServer (`bool`)
- fail (`bool`)
- conversationStatus (`SKYMessageConversationStatus`)

Part 4.1 (In `MessagesViewController.swift`)
```swift
// We need to firstly create a SKYMessage object with body, creatorUserRecordID.
let message = SKYMessage()!
message.body = text
message.creatorUserRecordID = SKYContainer.default().currentUserRecordID // The creator ID is the ID of the current user
// Send the message to the conversation
chat.addMessage(message, to: (conversation?.conversation)!, completion: { (msg, _) in
    if let sentMessage = msg {
        guard let transientMessageIndex = self.messages.index(of: message) else {
            return
        }

        self.messages[transientMessageIndex] = sentMessage
        self.collectionView.reloadData()
    }
})
```

## Part 5 - Create Direct Chat or Group Chat
In `SKYChatKit`, we use `SKYConversation` to create conversation.

There are two location in the tutorial app that is creating the conversation. The first one is in the `DirectConversationsViewController.swift`. (Marked as Part 5.1)

### Direct Chat
Part 5.1 (In `DirectConversationsViewController.swift`)
```swift
chat.createDirectConversation(userID: userRecord.recordID.recordName,
                              title: "",
                              metadata: nil) { (c, err) in
                                if let error = err {
                                    completion(nil, error)
                                    return
                                }

                                if let userConversation = c {
                                    self.userConversations[userRecord.recordID] = userConversation
                                    completion(userConversation, nil)
                                }
}
```

The function `createDirectConversation(userID: String, title: String, metadata: <String, Any>, completion: SKYChatUserConversationCompletion)` can create a direct conversation with a userID.

### Group Chat
If you would like to create a conversation with multiple userIDs, you may try to use another function `createConversation(participantsID: [String], title: String, metadata: <String, Any>, completion: SKYChatUserConversationCompletion)`. With this function you can pass multiple userIds to create conversation among them.

You may see the usage in `ConversationsViewController.swift`

Part 5.2 (In `ConversationsViewController.swift`)
```swift
chat?.createConversation(participantIDs: viewController.participantIDs,
                         title: title,
                         metadata: nil,
                         completion: { (userConversation, error) in
                            hud.hide(animated: true)
                            if error != nil {
                                let alert = UIAlertController(title: "Unable to Create",
                                                  message: error!.localizedDescription,
                                                  preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                self.present(alert, animated: true, completion: nil)
                                return
                            }

                            self.conversations.insert(userConversation!, at: 0)
                            self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)],
                                                      with: .automatic)

                            self.performSegue(withIdentifier: "open_conversation", sender: self)

})
```

## Part 6 - Leave a conversation
The function `leave(conversationID: String, completion: ((Error?) -> Void)?)` can be used for leaving a conversation by its ID. 

Part 6.1 (In `ConvserationDetailViewController.swift`)
```swift
chat.leave(conversationID: conversationID!) { (error) in
    hud.hide(animated: true)
    if error != nil {
        let alert = UIAlertController(title: "Unable to Leave Conversation",
                                      message: error!.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
        return
    }

    let _ = self.navigationController?.popToRootViewController(animated: true)
}
```

You may also use another function `leave(conversation: SKYConversation, completion: ((Error?) -> Void)?)`. Documnetaion [here](http://cocoadocs.org/docsets/SKYKitChat/0.0.1/Classes/SKYChatExtension.html#//api/name/leaveConversation:completion:).

## Part 7 - Trigger a typing event
The `SKYChatKit` provide a function for sending the typing indicator to the conversation participants. The users in the convseration can know who is now typing.

Part 7.1 (In `MessagesViewController.swift`)
```swift
func triggerTypingEvent(_ event: SKYChatTypingEvent) {
    if event == lastTypingEvent {
        if lastTypingEventDate != nil && lastTypingEventDate!.timeIntervalSinceNow > -1 {
            // Last event is published less than 1 second ago.
            // Throttle so the server is not overwhelmed with typing events.
            return
        }
    } else if event == .pause && event != .begin {
        // No need to send the pause typing event when typing not yet started.
        return
    }
    chat.sendTypingIndicator(event, in: (conversation?.conversation)!)
    lastTypingEvent = event
    lastTypingEventDate = Date.init()
}
```

The function `sendTypingIndicator(typingEvent: SKYChatTypingEvent, in:SKYConversation)` is called for sending out the different typing event.

The `SKYChatTypingEvent` includes:
- begin
- pause
- finished

## Part 8 - Subscribe to new message

Part 8.1 (In `MessagesViewController.swift`)
```swift
messageObserver = chat.subscribeToMessages(in: userConversation.conversation, handler: { (event, message) in
    print("Received message event")
})
```

You can use the function `subscribeToMessages(in: SKYConversation, handler: (SKYChatRecordChangeEvent, SKYMessage) -> Void)` for getting the new messages record change event in real time.

The `SKYChatRecordChangeEvent` consist of three type of events:
- create
- delete
- update

The action to be done when received an event can be defined in the handler. For example:
```swift
messageObserver = chat.subscribeToMessages(in: userConversation.conversation, handler: { (event, message) in
    print("Received message event")
    if event == SKYChatRecordChangeEvent.create && !self.messages.contains(message) && message.creatorUserRecordID != SKYContainer.default().currentUserRecordID
    {
        self.messages.append(message)
        self.reloadViews()
        self.finishReceivingMessage(animated: true)
    }
})
```

Only when the change event is create, the array of messages does not contain that message and that is not a sent message, the messages array will be appended and reload the view to show the latest message.


## Part 9 - Subscribe to Typing Indicator

Part 9.1 (In `MessagesViewController.swift`)
```swift
typingObserver = chat.subscribeToTypingIndicator(in: userConversation.conversation, handler: { (indicator) in
    print("Receiving typing event")
    self.promptTypingIndicator(indicator)
})
```

Function `subscribeToTypingIndicator (in: SKYUserConversation, handler: (SKYChatTypingIndicator) -> Void)` will receive every typing events in the conversation. 

Part 9.2 (In `MessagesViewController.swift`)
```swift
let typingUserIDs = indicator.typingUserIDs
if typingUserIDs.count == 0 {
    // No one is typing.
    self.navigationItem.prompt = nil;
    return;
} else if typingUserIDs.count == 1 {
    if let typingUser = ChatHelper.shared.userRecord(userID: typingUserIDs.first!) { // Get the first user record by first ID in typingUserIDs
        typingUserDisplayName = typingUser.chat_nameOfUserRecord // Get the displayname of the user record
    }

    if typingUserDisplayName != nil {
        self.navigationItem.prompt = "\(typingUserDisplayName!) is typing..."
    } else {
        self.navigationItem.prompt = "Someone is typing..."
    }
} else {
    self.navigationItem.prompt = "Some people are typing..."
}
```

`SKYChatTypingIndicator`:
- We can get an array of IDs of all users who are typing by accessing the `typingUserIDs`

## Part 10 - Fetch Conversations
We can fetch all the conversations that the user is involving by function of `SKYChatKit`:
```swift
fetchUserConversations(completion:SKYChatFetchUserConversationListCompletion?)
```

Part 10.1 (In `ConversationsViewController.swift`)
```swift
chat?.fetchUserConversations { (conversations, error) in
    // We fetched all the conversation of the current user in conversations
    if let err = error {
        let alert = UIAlertController(title: "Unable to load conversations", message: err.localizedDescription, preferredStyle: UIAlertControllerStyle.alert)
        self.present(alert, animated: true, completion: nil)
        return
    }

    if let fetchedConversations = conversations {
        print("Fetched \(fetchedConversations.count) user conversations.")
        self.conversations = fetchedConversations
    }

    self.tableView.reloadData()
    completion?()
}
```

There is two more methods to fetch the user conversation ([Documentation](http://cocoadocs.org/docsets/SKYKitChat/0.0.1/Classes/SKYChatExtension.html#//api/name/fetchUserConversationWithConversationID:completion:NS_SWIFT_NAME:)):
- `fetchUserConversation(conversationID: String, completion: SKYChatUserConversationCompletion?)`
- `fetchUserConversation(conversation: SKYConversation, completion: SKYChatUserConversationCompletion?)`

## Part 11 - Participants of conversation
We can retreive all the IDs of the participants by accessing the `participantIds` of `SKYConversation` under `SKYUserConversation`: 

```swift
let userconversation: SKYUserConversation? = nil
userconversation.conversation.participantIds
```

Part 11.1 (In `MessagesViewController.swift`)
```swift

for recordName in (conversation?.conversation.participantIds)! {
    userRecordIDs.append(SKYRecordID(recordType: "user", name: recordName))
}
```

We will get to record ids of the participant users into the `userRecordIDs`.

To get the user record by the ids, we need to fetch the record from the Cloud Database. 

Part 11.2 (In` MessagesViewController.swift`)
```swift
db?.fetchRecords(withIDs: userRecordIDs,
                 completionHandler: { (usermap, err) in
                    var newUsers: [String : SKYRecord] = [:]
                    for (k, v) in usermap! {
                        guard let recordID = k as? SKYRecordID else {
                            continue
                        }
                        guard let userRecord = v as? SKYRecord else {
                            continue
                        }
                        newUsers[recordID.recordName] = userRecord
                    }
                    self.users = newUsers
                    self.reloadViews()
}, perRecordErrorHandler: nil)
```

After this operation, we should have mapped the user id with the `SKYRecord`.

## Part 12 - Unread Count
Part 12.1 (In `ConversationsViewController.swift`)
```swift
chat?.fetchTotalUnreadCount(completion: { (dict, error) in
    if let unreadMessages = dict?["message"]?.intValue {
        self.navigationController?.tabBarItem.badgeValue = unreadMessages > 0 ? String(unreadMessages) : nil
    }
})
```

The function `fetchTotalUnreadCount(completion:SKYChatUnreadCOuntCOmpletion?)` can fetch the unread count in all conversations.

You may try to use `fetchUnreadCount(userConversation: SKYUserConversation, completion: SKYChatUnreadCountCompletion?)` to get the unread count in particular conversation.

## Part 13 - Chat History
We can fetch the messages of a particular `SKYConversation` by the function `fetchMessages(conversation: SKYConversation, limit: Int, beforeTime: Date?, completion: SKYChatFetchMessagesListCompletion?)`. 

You may have the limit of the messages to retrieve (`limit: Int`)and the time limit for the messages (`beforeTime: Data?`).

Part 13.1 (In `MessagesViewController.swift`)
```swift
chat.fetchMessages(conversation: conversation.conversation,
                    limit: 100,
                    beforeTime: nil,
                    completion: { (messages, error) in
                        if let err = error {
                            let alert = UIAlertController(title: "Unable to load", message: err.localizedDescription, preferredStyle: UIAlertControllerStyle.alert)
                            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                            return
                        }

                        if let messages = messages {
                            self.messages = messages.reversed()
                            self.reloadViews()
                        }
})
```

## Part 14 - Notification
There is serveral `NSNotification.Name` extentions from SKYKit, including:
- `SKYContainerDidChangeCurrentUser`
- `SKYChatDidReceiveRecordChange`
- `SKYContainerDidRegisterDevice`
- `SKYRecordSotrageUpdateAvailable`
- `SKYChatDidReceiveTypingIndicator`
- `SKYRecordStorageDidSynchronizeChanges`
- `SKYRecordStorageWillSynchronizeChanges`

In `RootViewController`, we want to keep track of the change of current user. If the current user is changed, we need to present the `LoginViewController` for signing up or logging in.

Part 14.1 (In `RootViewController.swift`)
```swift
NotificationCenter.default.addObserver(forName: NSNotification.Name.SKYContainerDidChangeCurrentUser,
                                       object: nil,
                                       queue: OperationQueue.main) { (note) in
                                        if !self.helper.isLoggedIn && !self.loginViewControllerPresenting {
                                            self.presentLoginViewController(animated: true)
                                        }

}
```

In `ChatHelper`, we also want to keep track of the change of current user. The fetching of current user record will be done and clear the current user records when we received any notification on the current user.

Part 14.2 (In `ChatHelper.swift`)
```swift
NotificationCenter.default.addObserver(forName: NSNotification.Name.SKYContainerDidChangeCurrentUser,
                                       object: nil,
                                       queue: OperationQueue.main) { (note) in
                                        self.fetchCurrentUserRecord(completion: { (_) in

                                        })
                                        self.userRecords = [:]
}
```

Similiar operation is also done in `UsersViewController`.

Part 14.3 (In `UsersViewController.swift`) 
```swift
NotificationCenter.default.addObserver(forName: NSNotification.Name.SKYContainerDidChangeCurrentUser,
                                       object: nil,
                                       queue: OperationQueue.main) { (note) in
                                        self.clearAllUserRecords()
}
```
