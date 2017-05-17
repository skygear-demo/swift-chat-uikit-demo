//
//  AppDelegate.swift
//  Swift Chat Demo
//
//  Created by atwork on 29/11/2016.
//  Copyright © 2016 Skygear. All rights reserved.
//

import UIKit
import UserNotifications
import SKYKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var skygear: SKYContainer {
        return SKYContainer.default()!
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        self.skygear.configAddress("http://localhost:3001")
        self.skygear.configure(withAPIKey: "my_skygear_key")
        self.skygear.registerDeviceCompletionHandler { (deviceID, error) in
            guard error == nil else {
                print("Got error when register device: \(error!.localizedDescription)")
                return
            }

            if let id = deviceID {
                print("Registered device with ID: \(id)")
            } else {
                print("Got nil device ID")
            }
        }

        let notificationCneter = UNUserNotificationCenter.current()
        notificationCneter.requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
            guard error == nil else {
                print("Failed to authorize: \(error!.localizedDescription)")
                return
            }

            guard granted else {
                print("Authorization not granted")
                return
            }

            application.registerForRemoteNotifications()
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        application.applicationIconBadgeNumber = 0
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("Got remote notification device token")
        self.skygear.registerRemoteNotificationDeviceToken(deviceToken) {(_, error) in
            guard error == nil else {
                print("Got error when register push notification token: \(error!.localizedDescription)")
                return
            }

            print("Successfully registered push notification token")
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Fail to get remote notification device token: \(error.localizedDescription)")
    }

}
