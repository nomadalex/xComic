//
//  ChooserViewController.swift
//  xComic
//
//  Created by Kun Wang on 4/25/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import UIKit
import CoreData
import SVProgressHUD

let smbWorkQueue = DispatchQueue(label: "com.ifreedomlife.xComic", attributes: [])

class ChooserViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UINavigationBarDelegate {

    fileprivate class Server {
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

    fileprivate static var lastSelectRecord: (server: Server, path: String)?

    fileprivate var servers = [Server]()
    fileprivate var pathStack = [String]()
    fileprivate var fileList = [String]()
    fileprivate var curServer: Server?

    fileprivate var isLoginMode = false

    @IBOutlet var navBar: UINavigationBar!
    @IBOutlet var tableView: UITableView!

    var documentURL: URL!
    var managedObjectContext: NSManagedObjectContext!

    private var selectedComic: ComicRecord?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let navItem = self.navBar.topItem!
        navItem.title = "Servers"
        navItem.rightBarButtonItem = UIBarButtonItem(title: "Login", style: .plain, target: self, action: #selector(enterLoginMode))

        if let (server, path) = ChooserViewController.lastSelectRecord {
            servers.append(server)
            curServer = server
            pathStack.append("\(server.ipStr)")
            pushNavItemWithTitle(server.name, animated: false)
            SVProgressHUD.show(with: .gradient)
            smbWorkQueue.async {
                let ss = SMBClient.sharedInstance
                if !ss.isConnected(server.name, withUser: server.username) {
                    if ss.isConnected(server.name) {
                        ss.disconnect(server.name)
                    }

                    guard ss.connect(server.name, ip: server.ip, username: server.username, password: server.password) else {
                        DispatchQueue.main.async {
                            _ = self.pathStack.popLast()
                            self.navBar.popItem(animated: false)
                            SVProgressHUD.dismiss()
                        }
                        return
                    }
                }

                let fm = SMBFileManager.sharedInstance
                guard fm.changeCurrentDirectoryPath("/\(server.ipStr)/\(path)") else {
                    DispatchQueue.main.async {
                        _ = self.pathStack.popLast()
                        self.navBar.popItem(animated: false)
                        SVProgressHUD.dismiss()
                    }
                    return
                }
                let fileList = fm.contentsOfDirectoryAtPath("").filter({ fm.directoryExistsAtPath($0) }).sorted(by: { $0 < $1 })
                DispatchQueue.main.async {
                    for p in path.components(separatedBy: "/") {
                        self.pathStack.append(p)
                        self.pushNavItemWithTitle(p, animated: false)
                    }
                    self.fileList = fileList
                    self.tableView.reloadData()
                    SVProgressHUD.dismiss()
                }
            }
        }

        _ = SMBClient.sharedInstance.startDiscoveryWithTimeout(added:
            { entry in
                if self.servers.index(where: { $0.name == entry.name }) == nil {
                    self.servers.append(Server(name: entry.name, ip: entry.ip, ipStr: entry.ipStr()))
                    if self.pathStack.isEmpty {
                        let indexPath = IndexPath(row: self.servers.endIndex-1, section: 0)
                        self.tableView.insertRows(at: [indexPath], with: .automatic)
                    }
                }
            }, removed:
            { entry in
                if let idx = self.servers.index(where: { $0.name == entry.name }) {
                    let indexPath = IndexPath(row: idx, section: 0)
                    self.servers.remove(at: idx)
                    if self.pathStack.isEmpty {
                        self.tableView.deleteRows(at: [indexPath], with: .fade)
                    }
                }
        })
    }

    deinit {
        SMBClient.sharedInstance.stopDiscovery()
    }

    func selectFolder(_ sender: AnyObject) {
        guard let srv = self.curServer else { return }
        let path = pathStack[pathStack.indices.suffix(from: 1)].joined(separator: "/")
        ChooserViewController.lastSelectRecord = (srv, path)

        SVProgressHUD.show(with: .gradient)
        smbWorkQueue.async(execute: { [unowned self] in
            let moc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            moc.parent = self.managedObjectContext
            self.selectedComic = self.addComicAtPath(moc, server: ServerEntry(name: srv.name, ip: srv.ip, username: srv.username, password: srv.password), path: path)

            do {
                try moc.save()
            } catch {
                fatalError("Can not save comic records")
            }
            DispatchQueue.main.async(execute: {
                SVProgressHUD.dismiss()
                if self.selectedComic != nil {
                    self.performSegue(withIdentifier: "showComic", sender: nil)
                }
            })
        })
    }

    private func getImagesInDir(_ path: String) -> [String] {
        let imgs = SMBFileManager.sharedInstance.contentsOfDirectoryAtPath(path).filter { fn in
            guard fn[fn.startIndex] != "." else { return false }
            let ext = (fn as NSString).pathExtension
            switch ext.lowercased() {
            case "jpg", "jpeg", "png": return true
            default: return false
            }
        }
        return imgs
    }

    private func addComicAtPath(_ context: NSManagedObjectContext, server: ServerEntry, path: String) -> ComicRecord? {
        let fullPath = "/\(server.name)/\(path)"
        let imgs = getImagesInDir(fullPath).sorted{ $0 < $1 }
        guard !imgs.isEmpty else { return nil }
        let dirName = (path as NSString).lastPathComponent
        var comic = findComic(context, title: dirName)
        if let c = comic {
            c.server = server
            c.path = path
            c.images = imgs
            c.cur = max(0, min(imgs.count, Int(c.cur ?? 0))) as NSNumber
        } else {
            comic = ComicRecord(context: context, server: server, title: dirName, thumbnail: "", path: path, images: imgs)
        }
        return comic
    }
    
    private func findComic(_ context: NSManagedObjectContext, title: String) -> ComicRecord? {
        let r = NSFetchRequest<ComicRecord>()
        r.predicate = NSPredicate(format: "title == %@", title)
        do {
            let comics = try context.fetch(r)
            guard comics.count > 0 else { return nil }
            return comics[0]
        } catch {
            fatalError("Failed to fetch employees: \(error)")
        }
    }

    func enterLoginMode(_ sender: AnyObject) {
        let item = sender as! UIBarButtonItem
        item.title = "Done"
        item.action = #selector(exitLoginMode)
        isLoginMode = true
    }

    func exitLoginMode(_ sender: AnyObject) {
        let item = sender as! UIBarButtonItem
        item.title = "Login"
        item.action = #selector(enterLoginMode)
        isLoginMode = false
    }

    fileprivate func loginServer(_ idx: Int, username: String, password: String, completion: ((Bool) -> Void)?) {
        SVProgressHUD.show(with: .gradient)
        smbWorkQueue.async(execute: {
            let srv = self.servers[idx]
            let sm = SMBClient.sharedInstance

            if sm.isConnected(srv.name) {
                sm.disconnect(srv.name)
            }
            let succ = sm.connect(srv.name, ip: srv.ip, username: username, password: password)

            DispatchQueue.main.async(execute: {
                SVProgressHUD.dismiss()
                completion?(succ)
            })
        })
    }

    fileprivate func showLogin(_ idx: Int, completion: ((Bool) -> Void)?) {
        let alertController = UIAlertController(title: "Login", message: nil, preferredStyle: .alert)

        let loginAction = UIAlertAction(title: "Login", style: .default) { _ in
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

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion?(false)
        }

        alertController.addTextField { textField in
            textField.placeholder = "Login"
        }

        alertController.addTextField { textField in
            textField.placeholder = "Password"
            textField.isSecureTextEntry = true
        }

        alertController.addAction(loginAction)
        alertController.addAction(cancelAction)

        self.present(alertController, animated: true, completion: nil)
    }

    fileprivate func pushNavItemWithTitle(_ title: String, animated: Bool) {
        let item = UINavigationItem(title: title)
        if self.pathStack.count >= 2 {
            item.rightBarButtonItem = UIBarButtonItem(title: "Select", style: .plain, target: self, action: #selector(self.selectFolder))
        }
        self.navBar.pushItem(item, animated: animated)
    }

    fileprivate func navToNext(_ idx: Int) {
        func runInBackground(_ block: @escaping () -> (String, String, [String])?) {
            SVProgressHUD.show(with: .gradient)
            smbWorkQueue.async(execute: {
                let ret = block()
                DispatchQueue.main.async(execute: {
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

                _ = fm.changeCurrentDirectoryPath("/")
                guard fm.changeCurrentDirectoryPath(fn) else { return nil }
                let fileList = fm.contentsOfDirectoryAtPath("").filter({ fm.directoryExistsAtPath($0) }).sorted(by: { $0 < $1 })
                self.curServer = self.servers[idx]
                return (fn, title, fileList)
            })
        } else {
            let fn = fileList[idx]
            let title = fn

            runInBackground({
                guard fm.directoryExistsAtPath(fn) else { return nil }
                guard fm.changeCurrentDirectoryPath(fn) else { return nil }
                let fileList = fm.contentsOfDirectoryAtPath("").filter({ fm.directoryExistsAtPath($0) }).sorted(by: { $0 < $1 })
                return (fn, title, fileList)
            })
        }
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if isLoginMode {
            showLogin((indexPath as NSIndexPath).row) { succ in
                guard succ else { return }
                self.exitLoginMode(self.navBar.topItem!.rightBarButtonItem!)
                self.navToNext((indexPath as NSIndexPath).row)
            }
        } else {
            navToNext((indexPath as NSIndexPath).row)
        }

        return nil
    }

    func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool {
        _ = pathStack.popLast()
        if pathStack.isEmpty {
            self.curServer = nil
            tableView.reloadData()
            return true
        }

        let path = "/" + pathStack.joined(separator: "/")

        SVProgressHUD.show(with: .gradient)
        smbWorkQueue.async(execute: {
            let fm = SMBFileManager.sharedInstance
            let fileList: [String]?
            if fm.changeCurrentDirectoryPath(path) {
                fileList = fm.contentsOfDirectoryAtPath("").filter{ fm.directoryExistsAtPath($0) }
            } else {
                fileList = nil
            }

            DispatchQueue.main.async(execute: {
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

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showComic" {
            let controller = segue.destination as! ReaderViewController
            controller.comic = selectedComic
        }
    }

    // MARK: - Table View

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if pathStack.isEmpty {
            return servers.count
        } else {
            return fileList.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        if pathStack.isEmpty {
            let srv = self.servers[(indexPath as NSIndexPath).row]
            cell.textLabel!.text = "\(srv.name) + \(srv.ipStr)"
        } else {
            cell.textLabel!.text = self.fileList[(indexPath as NSIndexPath).row]
        }

        return cell
    }
}
