//
//  OTROMEMOSignalCoordinator.swift
//  ChatSecure
//
//  Created by David Chiles on 8/4/16.
//  Copyright © 2016 Chris Ballinger. All rights reserved.
//

import UIKit
import XMPPFramework
import YapDatabase

let kPepPrefix = "urn:xmpp:omemo:0"
let kPepDeviceList = kPepPrefix+":devicelist"
let kPepDeviceListNotify = kPepDeviceList+"+notify"
let kePepBundles = kPepPrefix+":bundles"


/** 
 * This is the glue between XMPP/OMEMO and Signal
 */
@objc public class OTROMEMOSignalCoordinator: NSObject {
    
    public let signalEncryptionManager:OTRAccountSignalEncryptionManager
    public let omemoStorageManager:OTROMEMOStorageManager
    public let accountYapKey:String
    public weak var omemoModule:OMEMOModule?
    public weak var omemoModuleQueue:dispatch_queue_t?
    private var myJID:XMPPJID? {
        get {
            return omemoModule?.xmppStream.myJID
        }
    }
    let workQueue:dispatch_queue_t
    
    @objc public init(accountYapKey:String,  databaseConnection:YapDatabaseConnection) {
        self.signalEncryptionManager = OTRAccountSignalEncryptionManager(accountKey: accountYapKey,databaseConnection: databaseConnection)
        self.omemoStorageManager = OTROMEMOStorageManager(accountKey: accountYapKey, accountCollection: OTRAccount.collection(), databaseConnection: databaseConnection)
        self.accountYapKey = accountYapKey
        self.workQueue = dispatch_queue_create("OTROMEMOSignalCoordinator-work-queue", DISPATCH_QUEUE_SERIAL)
    }
    
    private func isOurJID(jid:XMPPJID) -> Bool {
        guard let ourJID = self.myJID else {
            return false;
        }
        
        return jid.isEqualToJID(ourJID, options: XMPPJIDCompareBare)
    }

}

//extension OTROMEMOSignalCoordinator:OMEMODelegate {
//    
//    /**
//     * In order to determine whether a given contact has devices that support OMEMO, the devicelist node in PEP is consulted. Devices MUST subscribe to 'urn:xmpp:omemo:0:devicelist' via PEP, so that they are informed whenever their contacts add a new device. They MUST cache the most up-to-date version of the devicelist.
//     */
//    public func omemo(omemo: OMEMOModule, deviceListUpdate deviceIds: [NSNumber], fromJID: XMPPJID, message: XMPPMessage) {
//        //print("device List Update \(deviceIds) \(fromJID) \(message)")
//        //print("\n")
//    }
//}

extension OTROMEMOSignalCoordinator { //OMEMOStorageDelegate
    
    public func configureWithParent(aParent: OMEMOModule, queue: dispatch_queue_t) -> Bool {
        self.omemoModule = aParent
        self.omemoModuleQueue = queue
        return true
    }
    
    public func storeDeviceIds(deviceIds: [NSNumber], forJID jid: XMPPJID) {
        
        let isOurDeviceList = self.isOurJID(jid)
        
        if (isOurDeviceList) {
            self.omemoStorageManager.storeOurDevices(deviceIds)
        } else {
            self.omemoStorageManager.storeBuddyDevices(deviceIds, buddyUsername: jid.bare())
        }
    }
    
    public func fetchDeviceIdsForJID(jid: XMPPJID) -> [NSNumber] {
        var devices:[OTROMEMODevice]?
        if self.isOurJID(jid) {
            devices = self.omemoStorageManager.getDevicesForOurAccount()
            
        } else {
            devices = self.omemoStorageManager.getDevicesForBuddy(jid.bare())
        }
        
        return (devices?.map({ (device) -> NSNumber in
            return device.deviceId
        })) ?? [NSNumber]()
        
    }

    // not sure why we need this yet??
    //Always returns most complete bundle with correct count of prekeys
//    public func fetchMyBundle() -> OMEMOBundle {
//        
//        guard let bundle = self.signalEncryptionManager.storage.fetchOurExistingBundle() else {
//            let outgoingBundle = self.signalEncryptionManager.generateOutgoingBundle()
//        }
//    }
    
    public func myDeviceId() -> NSNumber {
        return NSNumber(unsignedInt: self.signalEncryptionManager.registrationId)
    }

    public func isSessionValid(jid: XMPPJID, deviceId: NSNumber) -> Bool {
        return self.signalEncryptionManager.sessionRecordExistsForUsername(jid.bare(), deviceId: deviceId.intValue)
    }
}

extension OTROMEMOSignalCoordinator:XMPPStreamDelegate {
    public func xmppStreamDidAuthenticate(sender: XMPPStream!) {
        //TODO: Need to figure out when to do this. Especially on first connection when a device won't come down. When should we send one up
        //When do we need to explicity fetch and when do we depend on PEP to just send us stuff
//        let outgoingBundle = self.signalEncryptionManager.generateOutgoingBundle()
//        let deviceId = self.signalEncryptionManager.registrationId
//        let deviceNumber = NSNumber(unsignedInt: deviceId)
//        self.omemoModule?.publishDeviceIds([deviceNumber])
        //Fetch PEP because we don't know if it's there or not. And we don't know how long to wait for it to be auto-pushed to us
        //Should probably do this later and make sure the server supports PEP.
//        if self.xmppTracker == nil {
//            self.xmppTracker = XMPPIDTracker(stream: sender, dispatchQueue: self.workQueue)
//        }
//        
//        let deviceGetIQ = XMPPIQ.omemo_iqfetchDevices(sender.myJID)
//        dispatch_async(self.workQueue) { 
//            
//        }
//        self.xmppTracker?.addElement(deviceGetIQ, block: { (object, info) in
//            print("\(object)")
//            }, timeout: 5.0)
//        sender.sendElement(deviceGetIQ);
    }
    
    public func xmppStream(sender: XMPPStream!, didReceiveMessage message: XMPPMessage!) {
        guard let _ = message.elementForName("event", xmlns: XMLNS_PUBSUB_EVENT) else {
            return
        }
        if (sender.myJID.isEqualToJID(message.from(), options: XMPPJIDCompareBare)) {
            //This is our own PEP
            if var deviceList = message.omemo_deviceList() {
                let deviceNumber = NSNumber(unsignedInt: self.signalEncryptionManager.registrationId)
                if !deviceList.contains(deviceNumber) {
                    //Need to add device
                    deviceList.append(deviceNumber)
                    self.omemoModule?.publishDeviceIds(deviceList)
                    
                }
            }
        } else {
            //This is someone elses PEP
        }
    }
}

extension OTROMEMOSignalCoordinator:XMPPCapabilitiesDelegate {
    public func myFeaturesForXMPPCapabilities(sender: XMPPCapabilities!) -> [AnyObject]!{
        
        return [kPepDeviceList,kPepDeviceListNotify]
    }
    
}