//
//  AppDelegate.swift
//  UVCStreamer
//
//  Created by Dmitry Matyushkin on 06/01/2019.
//  Copyright © 2019 Dmitry Matyushkin. All rights reserved.
//

import Cocoa
import IOKit.pwr_mgt

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private var assertionID: IOPMAssertionID = 0

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let _ = IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                     "" as CFString,
                                     &self.assertionID )
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if self.assertionID != 0 {
            _ = IOPMAssertionRelease(self.assertionID)
        }
    }


}

