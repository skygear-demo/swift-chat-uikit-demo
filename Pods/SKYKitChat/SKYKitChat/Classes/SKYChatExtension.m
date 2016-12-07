//
//  SKYChatExtension.m
//  SKYKitChat
//
//  Copyright 2016 Oursky Ltd.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "SKYChatExtension.h"
#import "SKYChatExtension_Private.h"

#import <SKYKit/SKYKit.h>

#import "SKYChatReceipt.h"
#import "SKYChatRecordChange_Private.h"
#import "SKYChatTypingIndicator_Private.h"
#import "SKYConversation.h"
#import "SKYMessage.h"
#import "SKYPubsub.h"
#import "SKYReference.h"
#import "SKYUserChannel.h"
#import "SKYUserConversation.h"

NSString *const SKYChatMessageUnreadCountKey = @"message";
NSString *const SKYChatConversationUnreadCountKey = @"conversation";

NSString *const SKYChatDidReceiveTypingIndicatorNotification =
    @"SKYChatDidReceiveTypingIndicatorNotification";
NSString *const SKYChatDidReceiveRecordChangeNotification =
    @"SKYChatDidReceiveRecordChangeNotification";

NSString *const SKYChatTypingIndicatorUserInfoKey = @"typingIndicator";
NSString *const SKYChatRecordChangeUserInfoKey = @"recordChange";

@implementation SKYChatExtension {
    id notificationObserver;
    SKYUserChannel *subscribedUserChannel;
}

- (instancetype)initWithContainer:(SKYContainer *_Nonnull)container
{
    if ((self = [super init])) {
        if (!container) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException
                                           reason:@"container cannot be null"
                                         userInfo:nil];
        }
        _container = container;
        _automaticallyMarkMessagesAsDelivered = YES;

        notificationObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:SKYContainerDidChangeCurrentUserNotification
                        object:container
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *_Nonnull note) {
                        // Unsubscribe because the current user has changed. We do not
                        // want the UI to keep notified for changes intended for previous user.
                        [self unsubscribeFromUserChannel];
                    }];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:notificationObserver];
}

#pragma mark - Conversations

- (void)fetchDistinctConversationWithParticipantIDs:(NSArray<NSString *> *)participantIDs
                                         completion:(SKYChatConversationCompletion)completion
{
    NSMutableArray *predicates = [NSMutableArray array];
    [predicates addObject:[NSPredicate predicateWithFormat:@"distinct_by_participants = %@", @YES]];
    for (NSString *participantID in participantIDs) {
        [predicates
            addObject:[NSPredicate predicateWithFormat:@"%@ in participant_ids", participantID]];
    }
    [predicates addObject:[NSPredicate predicateWithFormat:@"participant_count = %@",
                                                           @(participantIDs.count)]];
    NSPredicate *pred = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];

    SKYQuery *query = [SKYQuery queryWithRecordType:@"conversation" predicate:pred];
    query.limit = 1;

    SKYDatabase *database = self.container.publicCloudDatabase;
    [database performQuery:query
         completionHandler:^(NSArray *results, NSError *error) {
             if (!completion) {
                 return;
             }
             if (error) {
                 completion(nil, error);
             } else if (results.count == 0) {
                 completion(nil, nil);
             } else {
                 SKYConversation *con = [SKYConversation recordWithRecord:results.firstObject];
                 completion(con, nil);
             }
         }];
}

- (void)createConversationWithParticipantIDs:(NSArray<NSString *> *)participantIDs
                                       title:(NSString *)title
                                    metadata:(NSDictionary<NSString *, id> *)metadata
                                  completion:(SKYChatUserConversationCompletion)completion
{
    [self createConversationWithParticipantIDs:participantIDs
                                         title:title
                                      metadata:metadata
                                      adminIDs:nil
                        distinctByParticipants:NO
                                    completion:completion];
}

- (void)createConversationWithParticipantIDs:(NSArray<NSString *> *)participantIDs
                                       title:(NSString *)title
                                    metadata:(NSDictionary<NSString *, id> *)metadata
                                    adminIDs:(NSArray<NSString *> *)adminIDs
                      distinctByParticipants:(BOOL)distinctByParticipants
                                  completion:(SKYChatUserConversationCompletion)completion
{
    if (!participantIDs || participantIDs.count == 0) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"cannot create conversation with no participants"
                                     userInfo:nil];
    }

    if (participantIDs.count == 1 &&
        [participantIDs.firstObject isEqualToString:self.container.currentUserRecordID]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"cannot create conversation with yourself"
                                     userInfo:nil];
    }

    if (![participantIDs containsObject:self.container.currentUserRecordID]) {
        participantIDs = [participantIDs arrayByAddingObject:self.container.currentUserRecordID];
    }
    participantIDs = [[NSSet setWithArray:participantIDs] allObjects];

    if (!adminIDs || adminIDs.count == 0) {
        adminIDs = [participantIDs copy];
    } else if (![adminIDs containsObject:self.container.currentUserRecordID]) {
        adminIDs = [adminIDs arrayByAddingObject:self.container.currentUserRecordID];
    }
    adminIDs = [[NSSet setWithArray:adminIDs] allObjects];

    SKYConversation *newConversation = [SKYConversation recordWithRecordType:@"conversation"];
    newConversation.participantIds = participantIDs;
    newConversation.adminIds = adminIDs;
    newConversation.metadata = metadata;
    newConversation.distinctByParticipants = distinctByParticipants;

    if (!distinctByParticipants) {
        // When distinctByParticipants is NO, we do not need to look for exisitng conversation first
        // as a new one will be created.
        [self saveConversation:newConversation completeWithUserConversation:completion];
        return;
    }

    [self fetchDistinctConversationWithParticipantIDs:participantIDs
                                           completion:^(SKYConversation *conversation,
                                                        NSError *error) {
                                               if (!completion) {
                                                   return;
                                               }

                                               if (error) {
                                                   completion(nil, error);
                                                   return;
                                               }

                                               if (conversation) {
                                                   [self fetchUserConversationWithConversation:
                                                             conversation
                                                                                    completion:
                                                                                        completion];
                                               } else {
                                                   [self saveConversation:newConversation
                                                       completeWithUserConversation:completion];
                                               }
                                           }];
}

- (void)createDirectConversationWithUserID:(NSString *)userID
                                     title:(NSString *)title
                                  metadata:(NSDictionary<NSString *, id> *)metadata
                                completion:(SKYChatUserConversationCompletion)completion
{
    [self createConversationWithParticipantIDs:@[ userID ]
                                         title:title
                                      metadata:metadata
                                      adminIDs:nil
                        distinctByParticipants:YES
                                    completion:completion];
}

- (void)saveConversation:(SKYConversation *)conversation
              completion:(SKYChatConversationCompletion)completion
{
    [self.container.publicCloudDatabase saveRecord:conversation
                                        completion:^(SKYRecord *record, NSError *error) {
                                            if (!completion) {
                                                return;
                                            }

                                            if (error) {
                                                completion(nil, error);
                                            }

                                            SKYConversation *newConversation =
                                                [SKYConversation recordWithRecord:record];
                                            completion(newConversation, error);
                                        }];
}

- (void)saveConversation:(SKYConversation *)conversation
    completeWithUserConversation:(SKYChatUserConversationCompletion)completion
{
    [self saveConversation:conversation
                completion:^(SKYConversation *_Nullable conversation, NSError *_Nullable error) {
                    if (!completion) {
                        return;
                    }

                    if (error) {
                        completion(nil, error);
                    }

                    if (conversation) {
                        [self fetchUserConversationWithConversation:conversation
                                                         completion:completion];
                    }
                }];
}

#pragma mark Fetching User Conversations

- (void)fetchUserConversationsWithQuery:(SKYQuery *)query
                             completion:(SKYChatFetchUserConversationListCompletion)completion
{
    query.transientIncludes = @{
        @"conversation" : [NSExpression expressionForKeyPath:@"conversation"],
        @"user" : [NSExpression expressionForKeyPath:@"user"],
        @"last_read_message" : [NSExpression expressionForKeyPath:@"last_read_message"]
    };

    SKYDatabase *database = self.container.publicCloudDatabase;
    [database performQuery:query
         completionHandler:^(NSArray *results, NSError *error) {
             NSMutableArray *resultArray = [[NSMutableArray alloc] init];
             for (SKYRecord *record in results) {
                 NSLog(@"record :%@", [record transient]);
                 SKYUserConversation *con = [SKYUserConversation recordWithRecord:record];
                 [resultArray addObject:con];
             }

             if (completion) {
                 completion(resultArray, error);
             }
         }];
}

- (void)fetchUserConversationsWithCompletion:(SKYChatFetchUserConversationListCompletion)completion
{
    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:@"user = %@", self.container.currentUserRecordID];
    SKYQuery *query = [SKYQuery queryWithRecordType:@"user_conversation" predicate:predicate];
    [self fetchUserConversationsWithQuery:query completion:completion];
}

- (void)fetchUserConversationWithConversationID:(NSString *)conversationId
                                     completion:(SKYChatUserConversationCompletion)completion
{
    NSPredicate *pred =
        [NSPredicate predicateWithFormat:@"user = %@ AND conversation = %@",
                                         self.container.currentUserRecordID, conversationId];
    SKYQuery *query = [SKYQuery queryWithRecordType:@"user_conversation" predicate:pred];
    query.limit = 1;
    [self fetchUserConversationsWithQuery:query
                               completion:^(NSArray<SKYUserConversation *> *conversationList,
                                            NSError *error) {
                                   if (!completion) {
                                       return;
                                   }

                                   if (!conversationList.count) {
                                       NSError *error =
                                           [NSError errorWithDomain:SKYOperationErrorDomain
                                                               code:SKYErrorResourceNotFound
                                                           userInfo:nil];
                                       completion(@[], error);
                                   }

                                   SKYUserConversation *con = conversationList.firstObject;
                                   completion(con, nil);
                               }];
}

- (void)fetchUserConversationWithConversation:(SKYConversation *)conversation
                                   completion:(SKYChatUserConversationCompletion)completion
{
    [self fetchUserConversationWithConversationID:conversation.recordID.recordName
                                       completion:completion];
}

#pragma mark Conversation Memberships

- (void)addParticipantsWithUserIDs:(NSArray<NSString *> *)userIDs
                    toConversation:(SKYConversation *)conversation
                        completion:(SKYChatConversationCompletion)completion
{
    [conversation addParticipantsWithUserIDs:userIDs];
    [self saveConversation:conversation completion:completion];
}

- (void)removeParticipantsWithUserIDs:(NSArray<NSString *> *)userIDs
                     fromConversation:(SKYConversation *)conversation
                           completion:(SKYChatConversationCompletion)completion
{
    [conversation removeParticipantsWithUserIDs:userIDs];
    [self saveConversation:conversation completion:completion];
}

- (void)addAdminsWithUserIDs:(NSArray<NSString *> *)userIDs
              toConversation:(SKYConversation *)conversation
                  completion:(SKYChatConversationCompletion)completion
{
    [conversation addAdminsWithUserIDs:userIDs];
    [self saveConversation:conversation completion:completion];
}

- (void)removeAdminsWithUserIDs:(NSArray<NSString *> *)userIDs
               fromConversation:(SKYConversation *)conversation
                     completion:(SKYChatConversationCompletion)completion
{
    [conversation removeAdminsWithUserIDs:userIDs];
    [self saveConversation:conversation completion:completion];
}

- (void)leaveConversation:(SKYConversation *)conversation
               completion:(void (^)(NSError *error))completion
{
    [self leaveConversationWithConversationID:conversation.recordID.recordName
                                   completion:completion];
}

- (void)leaveConversationWithConversationID:(NSString *)conversationID
                                 completion:(void (^)(NSError *error))completion
{
    [self.container callLambda:@"chat:leave_conversation"
                     arguments:@[ conversationID ]
             completionHandler:^(NSDictionary *response, NSError *error) {
                 if (completion) {
                     completion(error);
                 }
             }];
}

#pragma mark - Messages

- (void)createMessageWithConversation:(SKYConversation *)conversation
                                 body:(NSString *)body
                             metadata:(NSDictionary *)metadata
                           completion:(SKYChatMessageCompletion)completion
{
    [self createMessageWithConversation:conversation
                                   body:body
                             attachment:nil
                               metadata:metadata
                             completion:completion];
}

- (void)createMessageWithConversation:(SKYConversation *)conversation
                                 body:(NSString *)body
                           attachment:(SKYAsset *)attachment
                             metadata:(NSDictionary *)metadata
                           completion:(SKYChatMessageCompletion)completion
{
    SKYMessage *message = [SKYMessage message];
    if (body) {
        message.body = body;
    }
    if (metadata) {
        message.metadata = metadata;
    }
    if (attachment) {
        message.attachment = attachment;
    }
    [self addMessage:message toConversation:conversation completion:completion];
}

- (void)saveMessage:(SKYMessage *)message completion:(SKYChatMessageCompletion)completion
{
    SKYDatabase *database = self.container.privateCloudDatabase;
    [database saveRecord:message
              completion:^(SKYRecord *record, NSError *error) {
                  SKYMessage *msg = nil;
                  if (error) {
                      message.alreadySyncToServer = false;
                      message.fail = true;
                  } else {
                      msg = [SKYMessage recordWithRecord:record];
                      msg.alreadySyncToServer = true;
                      msg.fail = false;
                  }
                  if (completion) {
                      completion(msg, error);
                  }
              }];
}

- (void)addMessage:(SKYMessage *)message
    toConversation:(SKYConversation *)conversation
        completion:(SKYChatMessageCompletion)completion
{
    message.conversationID = conversation.recordID.recordName;
    if (!message.attachment || message.attachment.url.isFileURL) {
        [self saveMessage:message completion:completion];
        return;
    }

    [self.container uploadAsset:message.attachment
              completionHandler:^(SKYAsset *uploadedAsset, NSError *error) {
                  if (error) {
                      NSLog(@"error uploading asset: %@", error);

                      // NOTE(cheungpat): No idea why we should save message when upload asset
                      // has failed, but this is the existing behavior.
                  } else {
                      message.attachment = uploadedAsset;
                  }
                  [self saveMessage:message completion:completion];
              }];
}

- (void)fetchMessagesWithConversation:(SKYConversation *)conversation
                                limit:(NSInteger)limit
                           beforeTime:(NSDate *)beforeTime
                           completion:(SKYChatFetchMessagesListCompletion)completion
{
    [self fetchMessagesWithConversationID:conversation.recordID.recordName
                                    limit:limit
                               beforeTime:beforeTime
                               completion:completion];
}

- (void)fetchMessagesWithConversationID:(NSString *)conversationId
                                  limit:(NSInteger)limit
                             beforeTime:(NSDate *)beforeTime
                             completion:(SKYChatFetchMessagesListCompletion)completion
{

    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:conversationId, @(limit), nil];
    if (beforeTime) {
        NSString *dateString = @"";
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"];
        dateString = [formatter stringFromDate:beforeTime];
        NSLog(@"dateString :%@", dateString);

        [arguments addObject:dateString];
    }

    [self.container callLambda:@"chat:get_messages"
                     arguments:arguments
             completionHandler:^(NSDictionary *response, NSError *error) {
                 if (error) {
                     NSLog(@"error calling hello:someone: %@", error);
                 }
                 NSLog(@"Received response = %@", response);
                 NSArray *resultArray = [response objectForKey:@"results"];
                 if (resultArray.count > 0) {
                     NSMutableArray *returnArray = [[NSMutableArray alloc] init];
                     for (NSDictionary *obj in resultArray) {
                         SKYRecordDeserializer *deserializer = [SKYRecordDeserializer deserializer];
                         SKYRecord *record = [deserializer recordWithDictionary:[obj copy]];

                         SKYMessage *msg = [SKYMessage recordWithRecord:record];
                         msg.alreadySyncToServer = true;
                         msg.fail = false;
                         if (msg) {
                             [returnArray addObject:msg];
                         }
                     }
                     completion(returnArray, error);

                     // The SDK notifies the server that these messages are received
                     // from the client side. The app developer is not required
                     // to call this method.
                     if (returnArray.count && self.automaticallyMarkMessagesAsDelivered) {
                         [self markDeliveredMessages:returnArray completion:nil];
                     }

                 } else {
                     completion(nil, error);
                 }

             }];
}

#pragma mark Delivery and Read Status

- (void)callLambda:(NSString *)lambda
        messageIDs:(NSArray<NSString *> *)messageIDs
        completion:(void (^)(NSError *error))completion
{
    [self.container callLambda:lambda
                     arguments:@[ messageIDs ]
             completionHandler:^(NSDictionary *dict, NSError *error) {
                 if (completion) {
                     completion(error);
                 }
             }];
}

- (void)markReadMessages:(NSArray<SKYMessage *> *)messages
              completion:(void (^)(NSError *error))completion
{
    NSMutableArray *recordIDs = [NSMutableArray array];
    [messages enumerateObjectsUsingBlock:^(SKYMessage *_Nonnull obj, NSUInteger idx,
                                           BOOL *_Nonnull stop) {
        [recordIDs addObject:obj.recordID.recordName];
    }];
    [self callLambda:@"chat:mark_as_read" messageIDs:recordIDs completion:completion];
}

- (void)markReadMessagesWithID:(NSArray<NSString *> *)messageIDs
                    completion:(void (^)(NSError *error))completion
{
    [self callLambda:@"chat:mark_as_read" messageIDs:messageIDs completion:completion];
}

- (void)markDeliveredMessages:(NSArray<SKYMessage *> *)messages
                   completion:(void (^)(NSError *error))completion
{
    NSMutableArray *recordIDs = [NSMutableArray array];
    [messages enumerateObjectsUsingBlock:^(SKYMessage *_Nonnull obj, NSUInteger idx,
                                           BOOL *_Nonnull stop) {
        [recordIDs addObject:obj.recordID.recordName];
    }];
    [self callLambda:@"chat:mark_as_delivered" messageIDs:recordIDs completion:completion];
}

- (void)markDeliveredMessagesWithID:(NSArray<NSString *> *)messageIDs
                         completion:(void (^)(NSError *error))completion
{
    [self callLambda:@"chat:mark_as_delivered" messageIDs:messageIDs completion:completion];
}

- (void)fetchReceiptsWithMessage:(SKYMessage *)message
                      completion:(void (^)(NSArray<SKYChatReceipt *> *, NSError *error))completion
{
    [self.container callLambda:@"chat:get_receipt"
                     arguments:message.recordID.recordName
             completionHandler:^(NSDictionary *dict, NSError *error) {
                 if (!completion) {
                     return;
                 }
                 if (error) {
                     completion(nil, error);
                 }

                 NSMutableArray *receipts = [NSMutableArray array];
                 for (NSDictionary *receiptDict in dict[@"receipts"]) {
                     SKYChatReceipt *receipt =
                         [[SKYChatReceipt alloc] initWithReceiptDictionary:receiptDict];
                     [receipts addObject:receipt];
                 }

                 completion(receipts, nil);
             }];
}

#pragma mark Message Markers

- (void)markLastReadMessage:(SKYMessage *)message
         inUserConversation:(SKYUserConversation *)userConversation
                 completion:(SKYChatUserConversationCompletion)completion
{
    userConversation.lastReadMessageID = [SKYReference referenceWithRecord:message];

    SKYDatabase *database = self.container.publicCloudDatabase;
    [database saveRecord:userConversation
              completion:^(SKYRecord *record, NSError *error) {
                  SKYUserConversation *con = [SKYUserConversation recordWithRecord:record];
                  if (completion) {
                      completion(con, error);
                  }
              }];
}

- (void)fetchUnreadCountWithUserConversation:(SKYUserConversation *)userConversation
                                  completion:(SKYChatUnreadCountCompletion)completion
{
    [self fetchUserConversationWithConversationID:userConversation.conversation.recordID.recordName
                                       completion:^(SKYUserConversation *conversation,
                                                    NSError *error) {
                                           if (!completion) {
                                               return;
                                           }
                                           if (error) {
                                               completion(nil, error);
                                               return;
                                           }
                                           NSDictionary *response = @{
                                               SKYChatMessageUnreadCountKey :
                                                   @(conversation.unreadCount),
                                           };
                                           completion(response, nil);
                                       }];
}

- (void)fetchTotalUnreadCount:(SKYChatUnreadCountCompletion)completion
{
    [self.container callLambda:@"chat:total_unread"
             completionHandler:^(NSDictionary *response, NSError *error) {
                 if (!completion) {
                     return;
                 }
                 if (error) {
                     completion(nil, error);
                 }

                 // Ensure the dictionary has correct type of classes
                 NSMutableDictionary *fixedResponse = [NSMutableDictionary dictionary];
                 [response enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                     if ([obj isKindOfClass:[NSNumber class]]) {
                         [fixedResponse setObject:obj forKey:key];
                     }
                 }];

                 completion(fixedResponse, error);

             }];
}

#pragma mark Typing Indicator

- (void)sendTypingIndicator:(SKYChatTypingEvent)typingEvent
             inConversation:(SKYConversation *)conversation
{
    [self sendTypingIndicator:typingEvent
               inConversation:conversation
                         date:[NSDate date]
                   completion:nil];
}

- (void)sendTypingIndicator:(SKYChatTypingEvent)typingEvent
             inConversation:(SKYConversation *)conversation
                       date:(NSDate *)date
                 completion:(void (^)(NSError *error))completion
{
    [self.container callLambda:@"chat:typing"
                     arguments:@[
                         conversation.recordID.recordName,
                         SKYChatTypingEventToString(typingEvent),
                         [SKYDataSerialization stringFromDate:date],
                     ]
             completionHandler:^(NSDictionary *dict, NSError *error) {
                 if (completion) {
                     completion(error);
                 }
             }];
}

#pragma mark - Subscriptions

- (void)fetchOrCreateUserChannelWithCompletion:(SKYChatChannelCompletion)completion
{
    [self fetchUserChannelWithCompletion:^(SKYUserChannel *_Nullable userChannel,
                                           NSError *_Nullable error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }

        if (!userChannel) {
            [self createUserChannelWithCompletion:completion];
            return;
        }

        if (completion) {
            completion(userChannel, nil);
        }
    }];
}

- (void)fetchUserChannelWithCompletion:(SKYChatChannelCompletion)completion
{
    SKYQuery *query = [SKYQuery queryWithRecordType:@"user_channel" predicate:nil];
    query.limit = 1;
    [self.container.privateCloudDatabase
             performQuery:query
        completionHandler:^(NSArray *results, NSError *error) {
            if (!completion) {
                return;
            }

            if (error || results.count == 0) {
                completion(nil, error);
                return;
            }

            completion([SKYUserChannel recordWithRecord:results.firstObject], error);
        }];
}

- (void)createUserChannelWithCompletion:(SKYChatChannelCompletion)completion
{
    SKYUserChannel *userChannel = [SKYUserChannel recordWithRecordType:@"user_channel"];
    userChannel.name = [[NSUUID UUID] UUIDString];
    [self.container.privateCloudDatabase saveRecord:userChannel
                                         completion:^(SKYRecord *record, NSError *error) {
                                             if (!completion) {
                                                 return;
                                             }

                                             if (error) {
                                                 completion(nil, error);
                                                 return;
                                             }

                                             SKYUserChannel *channel =
                                                 [SKYUserChannel recordWithRecord:record];
                                             completion(channel, error);
                                         }];
}

- (void)deleteAllUserChannelsWithCompletion:(void (^)(NSError *error))completion
{
    SKYQuery *query = [SKYQuery queryWithRecordType:@"user_channel" predicate:nil];
    [self.container.privateCloudDatabase
             performQuery:query
        completionHandler:^(NSArray *results, NSError *error) {
            if (error) {
                if (completion) {
                    completion(error);
                }
                return;
            }

            NSMutableArray *recordIDsToDelete = [NSMutableArray array];
            [results enumerateObjectsUsingBlock:^(SKYRecord *record, NSUInteger idx,
                                                  BOOL *_Nonnull stop) {
                [recordIDsToDelete addObject:record.recordID];
            }];

            if (!recordIDsToDelete.count) {
                if (completion) {
                    completion(nil);
                }
                return;
            }

            [self.container.privateCloudDatabase
                 deleteRecordsWithIDs:recordIDsToDelete
                    completionHandler:^(NSArray *deletedRecordIDs, NSError *error) {
                        if (completion) {
                            completion(error);
                        }
                    }
                perRecordErrorHandler:nil];
        }];
}

- (void)handleUserChannelDictionary:(NSDictionary<NSString *, id> *)dict
{
    NSString *dictionaryEventType = dict[@"event"];
    NSDictionary *data = dict[@"data"];
    if ([SKYChatTypingIndicator isTypingIndicatorEventType:dictionaryEventType]) {
        [data enumerateKeysAndObjectsUsingBlock:^(NSString *conversationIDString,
                                                  NSDictionary *userDict, BOOL *stop) {
            NSString *conversationID =
                [[SKYRecordID recordIDWithCanonicalString:conversationIDString] recordName];

            SKYChatTypingIndicator *indicator =
                [[SKYChatTypingIndicator alloc] initWithDictionary:userDict
                                                    conversationID:conversationID];

            [[NSNotificationCenter defaultCenter]
                postNotificationName:SKYChatDidReceiveTypingIndicatorNotification
                              object:self
                            userInfo:@{
                                SKYChatTypingIndicatorUserInfoKey : indicator,
                            }];
        }];
    } else if ([SKYChatRecordChange isRecordChangeEventType:dictionaryEventType]) {
        SKYChatRecordChange *recordChange = [[SKYChatRecordChange alloc] initWithDictionary:data];
        if (!recordChange) {
            return;
        }

        [[NSNotificationCenter defaultCenter]
            postNotificationName:SKYChatDidReceiveRecordChangeNotification
                          object:self
                        userInfo:@{
                            SKYChatRecordChangeUserInfoKey : recordChange,
                        }];
    }

    if (self.userChannelMessageHandler) {
        self.userChannelMessageHandler(dict);
    }
}

- (void)subscribeToUserChannelWithCompletion:(void (^)(NSError *error))completion
{
    if (subscribedUserChannel) {
        // Already subscribed. Do nothing except to call the completion handler.
        if (completion) {
            completion(nil);
        }
        return;
    }

    [self fetchOrCreateUserChannelWithCompletion:^(SKYUserChannel *userChannel, NSError *error) {
        if (error || !userChannel) {
            if (completion) {
                if (!error) {
                    error = [NSError errorWithDomain:SKYOperationErrorDomain
                                                code:SKYErrorResourceNotFound
                                            userInfo:nil];
                }
                completion(error);
            }
            return;
        }

        self->subscribedUserChannel = userChannel;
        [self.container.pubsubClient subscribeTo:userChannel.name
                                         handler:^(NSDictionary *data) {
                                             [self handleUserChannelDictionary:data];
                                         }];

        if (completion) {
            completion(nil);
        }
    }];
}

- (void)unsubscribeFromUserChannel
{
    if (subscribedUserChannel) {
        [self.container.pubsubClient unsubscribe:subscribedUserChannel.name];
        subscribedUserChannel = nil;
    }
}

- (id)subscribeToTypingIndicatorInConversation:(SKYConversation *)conversation
                                       handler:(void (^)(SKYChatTypingIndicator *indicator))handler
{
    if (!handler) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"must have handler"
                                     userInfo:nil];
    }

    [self subscribeToUserChannelWithCompletion:nil];

    NSString *conversationID = conversation.recordID.recordName;
    return [[NSNotificationCenter defaultCenter]
        addObserverForName:SKYChatDidReceiveTypingIndicatorNotification
                    object:self
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *_Nonnull note) {
                    SKYChatTypingIndicator *indicator =
                        [note.userInfo objectForKey:SKYChatTypingIndicatorUserInfoKey];
                    if ([indicator.conversationID isEqualToString:conversationID]) {
                        handler(indicator);
                    }
                }];
}

- (id)subscribeToMessagesInConversation:(SKYConversation *)conversation
                                handler:(void (^)(SKYChatRecordChangeEvent event,
                                                  SKYMessage *record))handler
{
    if (!handler) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"must have handler"
                                     userInfo:nil];
    }

    [self subscribeToUserChannelWithCompletion:nil];

    SKYRecordID *conversationID = conversation.recordID;
    return [[NSNotificationCenter defaultCenter]
        addObserverForName:SKYChatDidReceiveRecordChangeNotification
                    object:self
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *_Nonnull note) {
                    SKYChatRecordChange *recordChange =
                        [note.userInfo objectForKey:SKYChatRecordChangeUserInfoKey];
                    if (![recordChange.recordType isEqualToString:@"message"]) {
                        return;
                    }

                    SKYReference *ref = recordChange.record[@"conversation_id"];
                    if (![ref isKindOfClass:[SKYReference class]]) {
                        return;
                    }

                    if (![ref.recordID isEqualToRecordID:conversationID]) {
                        return;
                    }

                    handler(recordChange.event, [SKYMessage recordWithRecord:recordChange.record]);
                }];
}

@end
