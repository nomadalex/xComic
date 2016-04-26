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

class ChooserViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UINavigationBarDelegate {

    private struct Server {
        let name: String
        let ip: UInt32
        let ipStr: String
    }

    private var servers = [Server]()
    private var pathStack = [String]()
    private var fileList = [String]()

    private var isLoginMode = false

    var chooseCompletion: (([(String, String)]) -> Void)? = nil

    @IBOutlet var navBar: UINavigationBar!
    @IBOutlet var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let navItem = self.navBar.topItem!
        navItem.title = "Servers"
        navItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .Plain, target: self, action: #selector(dismissSelf))
        navItem.rightBarButtonItem = UIBarButtonItem(title: "Login", style: .Plain, target: self, action: #selector(enterLoginMode))

        SMBService.sharedInstance.startDiscoveryWithTimeout(added:
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
        SMBService.sharedInstance.stopDiscovery()
    }

    func dismissSelf(sender: AnyObject) {
        self.dismissViewControllerAnimated(true, completion: nil)
    }

    func selectFolder(sender: AnyObject) {
        let path = pathStack[1..<pathStack.endIndex].joinWithSeparator("/")
        dismissSelf(self)
        chooseCompletion?([(pathStack[0], path)])
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
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
            let srv = self.servers[idx]
            let sm = SMBService.sharedInstance

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

            self.loginServer(idx, username: loginTextField.text!, password: passwordTextField.text!) { succ in
                if succ {
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

    private func navToNext(idx: Int) {
        func runInBackground(block: () -> (String, String, [String])?) {
            SVProgressHUD.showWithMaskType(.Gradient)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
                let ret = block()
                dispatch_async(dispatch_get_main_queue(), {
                    if let (fn, title, fileList) = ret {
                        self.pathStack.append(fn)
                        let item = UINavigationItem(title: title)
                        if self.pathStack.count >= 2 {
                            item.rightBarButtonItem = UIBarButtonItem(title: "Select", style: .Plain, target: self, action: #selector(self.selectFolder))
                        }
                        self.navBar.pushNavigationItem(item, animated: true)
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
                if !SMBService.sharedInstance.isConnected(server.name) {
                    guard SMBService.sharedInstance.connect(server.name, ip: server.ip) else { return nil }
                }

                fm.changeCurrentDirectoryPath("/")
                guard fm.changeCurrentDirectoryPath(fn) else { return nil }
                let fileList = fm.contentsOfDirectoryAtPath("").filter{ fm.directoryExistsAtPath($0) }
                return (fn, title, fileList)
            })
        } else {
            let fn = fileList[idx]
            let title = fn

            runInBackground({
                guard fm.directoryExistsAtPath(fn) else { return nil }
                guard fm.changeCurrentDirectoryPath(fn) else { return nil }
                let fileList = fm.contentsOfDirectoryAtPath("").filter{ fm.directoryExistsAtPath($0) }
                return (fn, title, fileList)
            })
        }
    }

    func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        if isLoginMode {
            showLogin(indexPath.row) { succ in
                if succ {
                    self.exitLoginMode(self.navBar.topItem!.rightBarButtonItem!)
                    self.navToNext(indexPath.row)
                }
            }
        } else {
            navToNext(indexPath.row)
        }

        return nil
    }

    func navigationBar(navigationBar: UINavigationBar, shouldPopItem item: UINavigationItem) -> Bool {
        pathStack.popLast()
        if pathStack.isEmpty {
            tableView.reloadData()
            return true
        }

        let path = "/" + pathStack.joinWithSeparator("/")

        SVProgressHUD.showWithMaskType(.Gradient)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
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