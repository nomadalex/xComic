//
//  ChooserViewController.swift
//  xComic
//
//  Created by Kun Wang on 4/25/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import UIKit
import SVProgressHUD
import SMBClientSwift

class ChooserViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UINavigationBarDelegate {

    private class Server {
        let name: String
        let ip: UInt32
        let ipStr: String
        var username = ""
        var password = ""

        init(name: String, ip: UInt32, ipStr: String) {
            self.name = name
            self.ip = ip
            self.ipStr = ipStr
        }
    }

    private static var lastSelectRecord: (server: Server, path: String)?

    private var servers = [Server]()
    private var pathStack = [String]()
    private var fileList = [String]()
    private var curServer: Server?

    private var isLoginMode = false

    var chooseCompletion: (((ServerEntry, String)) -> Void)?

    @IBOutlet var navBar: UINavigationBar!
    @IBOutlet var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let navItem = self.navBar.topItem!
        navItem.title = "Servers"
        navItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .Plain, target: self, action: #selector(dismissSelf))
        navItem.rightBarButtonItem = UIBarButtonItem(title: "Login", style: .Plain, target: self, action: #selector(enterLoginMode))

        if let (server, path) = ChooserViewController.lastSelectRecord {
            servers.append(server)
            curServer = server
            pathStack.append("\(server.ipStr)")
            pushNavItemWithTitle(server.name, animated: false)
            SVProgressHUD.showWithMaskType(.Gradient)
            dispatch_async(smbWorkQueue) {
                let ss = SMBClient.sharedInstance
                if !ss.isConnected(server.name, withUser: server.username) {
                    if ss.isConnected(server.name) {
                        ss.disconnect(server.name)
                    }

                    guard ss.connect(server.name, ip: server.ip, username: server.username, password: server.password) else {
                        dispatch_async(dispatch_get_main_queue()) {
                            self.pathStack.popLast()
                            self.navBar.popNavigationItemAnimated(false)
                            SVProgressHUD.dismiss()
                        }
                        return
                    }
                }

                let fm = SMBFileManager.sharedInstance
                guard fm.changeCurrentDirectoryPath("/\(server.ipStr)/\(path)") else {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.pathStack.popLast()
                        self.navBar.popNavigationItemAnimated(false)
                        SVProgressHUD.dismiss()
                    }
                    return
                }
                let fileList = fm.contentsOfDirectoryAtPath("").filter({ fm.directoryExistsAtPath($0) }).sort({ $0 < $1 })
                dispatch_async(dispatch_get_main_queue()) {
                    for p in path.componentsSeparatedByString("/") {
                        self.pathStack.append(p)
                        self.pushNavItemWithTitle(p, animated: false)
                    }
                    self.fileList = fileList
                    self.tableView.reloadData()
                    SVProgressHUD.dismiss()
                }
            }
        }

        SMBClient.sharedInstance.startDiscoveryWithTimeout(added:
            { entry in
                if self.servers.indexOf({ $0.name == entry.name }) == nil {
                    self.servers.append(Server(name: entry.name, ip: entry.ip, ipStr: entry.ipStr()))
                    if self.pathStack.isEmpty {
                        let indexPath = NSIndexPath(forRow: self.servers.endIndex-1, inSection: 0)
                        self.tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
                    }
                }
            }, removed:
            { entry in
                if let idx = self.servers.indexOf({ $0.name == entry.name }) {
                    let indexPath = NSIndexPath(forRow: idx, inSection: 0)
                    self.servers.removeAtIndex(idx)
                    if self.pathStack.isEmpty {
                        self.tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
                    }
                }
        })
    }

    deinit {
        SMBClient.sharedInstance.stopDiscovery()
    }

    func dismissSelf(sender: AnyObject) {
        self.dismissViewControllerAnimated(true, completion: nil)
    }

    func selectFolder(sender: AnyObject) {
        let path = pathStack[1..<pathStack.endIndex].joinWithSeparator("/")
        dismissSelf(self)
        guard let srv = self.curServer else { return }
        ChooserViewController.lastSelectRecord = (srv, path)
        chooseCompletion?((ServerEntry(name: srv.name, ip: srv.ip, username: srv.username, password: srv.password), path))
    }

    func enterLoginMode(sender: AnyObject) {
        let item = sender as! UIBarButtonItem
        item.title = "Done"
        item.action = #selector(exitLoginMode)
        isLoginMode = true
    }

    func exitLoginMode(sender: AnyObject) {
        let item = sender as! UIBarButtonItem
        item.title = "Login"
        item.action = #selector(enterLoginMode)
        isLoginMode = false
    }

    private func loginServer(idx: Int, username: String, password: String, completion: ((Bool) -> Void)?) {
        SVProgressHUD.showWithMaskType(.Gradient)
        dispatch_async(smbWorkQueue, {
            let srv = self.servers[idx]
            let sm = SMBClient.sharedInstance

            if sm.isConnected(srv.name) {
                sm.disconnect(srv.name)
            }
            let succ = sm.connect(srv.name, ip: srv.ip, username: username, password: password)

            dispatch_async(dispatch_get_main_queue(), {
                SVProgressHUD.dismiss()
                completion?(succ)
            })
        })
    }

    private func showLogin(idx: Int, completion: ((Bool) -> Void)?) {
        let alertController = UIAlertController(title: "Login", message: nil, preferredStyle: .Alert)

        let loginAction = UIAlertAction(title: "Login", style: .Default) { _ in
            let loginTextField = alertController.textFields![0] as UITextField
            let passwordTextField = alertController.textFields![1] as UITextField

            let user = loginTextField.text!
            let pass = passwordTextField.text!
            self.loginServer(idx, username: user, password: pass) { succ in
                if succ {
                    let srv = self.servers[idx]
                    srv.username = user
                    srv.password = pass
                    completion?(true)
                } else {
                    self.showLogin(idx, completion: completion)
                }
            }
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel) { _ in
            completion?(false)
        }

        alertController.addTextFieldWithConfigurationHandler { textField in
            textField.placeholder = "Login"
        }

        alertController.addTextFieldWithConfigurationHandler { textField in
            textField.placeholder = "Password"
            textField.secureTextEntry = true
        }

        alertController.addAction(loginAction)
        alertController.addAction(cancelAction)

        self.presentViewController(alertController, animated: true, completion: nil)
    }

    private func pushNavItemWithTitle(title: String, animated: Bool) {
        let item = UINavigationItem(title: title)
        if self.pathStack.count >= 2 {
            item.rightBarButtonItem = UIBarButtonItem(title: "Select", style: .Plain, target: self, action: #selector(self.selectFolder))
        }
        self.navBar.pushNavigationItem(item, animated: animated)
    }

    private func navToNext(idx: Int) {
        func runInBackground(block: () -> (String, String, [String])?) {
            SVProgressHUD.showWithMaskType(.Gradient)
            dispatch_async(smbWorkQueue, {
                let ret = block()
                dispatch_async(dispatch_get_main_queue(), {
                    if let (fn, title, fileList) = ret {
                        self.pathStack.append(fn)
                        self.pushNavItemWithTitle(title, animated: true)
                        self.fileList = fileList
                        self.tableView.reloadData()
                    }
                    SVProgressHUD.dismiss()
                })
            })
        }

        let fm = SMBFileManager.sharedInstance

        if self.pathStack.isEmpty {
            let server = servers[idx]
            let fn = "\(server.ipStr)"
            let title = server.name

            runInBackground({
                if !SMBClient.sharedInstance.isConnected(server.name) {
                    guard SMBClient.sharedInstance.connect(server.name, ip: server.ip) else { return nil }
                }

                fm.changeCurrentDirectoryPath("/")
                guard fm.changeCurrentDirectoryPath(fn) else { return nil }
                let fileList = fm.contentsOfDirectoryAtPath("").filter({ fm.directoryExistsAtPath($0) }).sort({ $0 < $1 })
                self.curServer = self.servers[idx]
                return (fn, title, fileList)
            })
        } else {
            let fn = fileList[idx]
            let title = fn

            runInBackground({
                guard fm.directoryExistsAtPath(fn) else { return nil }
                guard fm.changeCurrentDirectoryPath(fn) else { return nil }
                let fileList = fm.contentsOfDirectoryAtPath("").filter({ fm.directoryExistsAtPath($0) }).sort({ $0 < $1 })
                return (fn, title, fileList)
            })
        }
    }

    func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        if isLoginMode {
            showLogin(indexPath.row) { succ in
                guard succ else { return }
                self.exitLoginMode(self.navBar.topItem!.rightBarButtonItem!)
                self.navToNext(indexPath.row)
            }
        } else {
            navToNext(indexPath.row)
        }

        return nil
    }

    func navigationBar(navigationBar: UINavigationBar, shouldPopItem item: UINavigationItem) -> Bool {
        pathStack.popLast()
        if pathStack.isEmpty {
            self.curServer = nil
            tableView.reloadData()
            return true
        }

        let path = "/" + pathStack.joinWithSeparator("/")

        SVProgressHUD.showWithMaskType(.Gradient)
        dispatch_async(smbWorkQueue, {
            let fm = SMBFileManager.sharedInstance
            let fileList: [String]?
            if fm.changeCurrentDirectoryPath(path) {
                fileList = fm.contentsOfDirectoryAtPath("").filter{ fm.directoryExistsAtPath($0) }
            } else {
                fileList = nil
            }

            dispatch_async(dispatch_get_main_queue(), {
                if fileList != nil {
                    self.fileList = fileList!
                } else {
                    self.pathStack.removeAll()
                    let items = self.navBar.items!
                    self.navBar.setItems([items.first!], animated: true)
                    self.curServer = nil
                }
                self.tableView.reloadData()
                SVProgressHUD.dismiss()
            })
        })
        return true
    }

    // MARK: - Segues

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
    }

    // MARK: - Table View

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if pathStack.isEmpty {
            return servers.count
        } else {
            return fileList.count
        }
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)

        if pathStack.isEmpty {
            let srv = self.servers[indexPath.row]
            cell.textLabel!.text = "\(srv.name) + \(srv.ipStr)"
        } else {
            cell.textLabel!.text = self.fileList[indexPath.row]
        }

        return cell
    }
}