//
//  LibraryViewController.swift
//  xComic
//
//  Created by Kun Wang on 4/25/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import UIKit
import SVProgressHUD
import CoreData
import PINCache
import SMBClientSwift

let smbWorkQueue = dispatch_queue_create("com.ifreedomlife.xComic", DISPATCH_QUEUE_SERIAL)

class LibraryCell: UITableViewCell {
    @IBOutlet
    var thumbnailImg: UIImageView!
    @IBOutlet
    var titleLabel: UILabel!
    @IBOutlet
    var progressLabel: UILabel!
    @IBOutlet
    var widthContraint: NSLayoutConstraint!
    @IBOutlet
    var heightContraint: NSLayoutConstraint!
}

class LibraryViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    private let fm = SMBFileManager.sharedInstance

    var documentURL: NSURL!
    var managedObjectContext: NSManagedObjectContext!

    private var comicFetchs: NSFetchedResultsController!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.navigationItem.leftBarButtonItem = self.editButtonItem()

        let optionButton = UIBarButtonItem(title: "Option", style: .Plain, target: self, action: #selector(showOptionMenu))
        self.navigationItem.rightBarButtonItem = optionButton

        initComicFetchs()
    }

    private func initComicFetchs() {
        let request = NSFetchRequest(entityName: "ComicRecord")
        let titleSort = NSSortDescriptor(key: "title", ascending: true)
        request.sortDescriptors = [titleSort]

        comicFetchs = NSFetchedResultsController(fetchRequest: request, managedObjectContext: managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        comicFetchs.delegate = self

        do {
            try comicFetchs.performFetch()
        } catch {
            fatalError("Failed to initialize FetchedResultsController: \(error)")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func showOptionMenu(sender: AnyObject) {
        let menu = UIAlertController(title: nil, message: "Choose Option", preferredStyle: .ActionSheet)

        menu.addAction(UIAlertAction(title: "Add", style: .Default, handler: showChooser))
        menu.addAction(UIAlertAction(title: "Clear Cache", style: .Default, handler: clearCache))
        menu.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))

        menu.popoverPresentationController!.barButtonItem = sender as? UIBarButtonItem
        self.presentViewController(menu, animated: true, completion: nil)
    }

    func showChooser(sender: AnyObject) {
        self.performSegueWithIdentifier("showComicChooser", sender: nil)
    }

    func clearCache(sender: AnyObject) {
        PINCache.sharedCache().removeAllObjects()
    }

    private func calcMD5(data: NSData) -> String {
        let digestLen = Int(CC_MD5_DIGEST_LENGTH)
        let result = UnsafeMutablePointer<CUnsignedChar>.alloc(digestLen)

        CC_MD5(data.bytes, UInt32(data.length), result)

        let hash = NSMutableString()
        for i in 0..<digestLen {
            hash.appendFormat("%02x", result[i])
        }

        result.dealloc(digestLen)
        
        return String(format: hash as String)
    }
    
    private func getImagesInDir(path: String) -> [String] {
        let imgs = fm.contentsOfDirectoryAtPath(path).filter { fn in
            guard fn[fn.startIndex] != "." else { return false }
            let ext = (fn as NSString).pathExtension
            switch ext.lowercaseString {
            case "jpg", "jpeg", "png": return true
            default: return false
            }
        }
        return imgs
    }

    private func generateThumbnail(img: UIImage, bounds: CGSize) -> UIImage {
        let horiRatio = bounds.width / img.size.width
        let vertRatio = bounds.height / img.size.height
        let ratio = min(horiRatio, vertRatio)
        let newSize = CGSize(width: img.size.width * ratio, height: img.size.height * ratio)

        UIGraphicsBeginImageContext(newSize)
        img.drawInRect(CGRect(origin: CGPoint.zero, size: newSize))
        let newImg = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImg
    }

    private func addComicAtPath(context: NSManagedObjectContext, server: ServerEntry, path: String) -> ComicRecord? {
        let dirName = (path as NSString).lastPathComponent
        let fullPath = "/\(server.name)/\(path)"
        let imgs = getImagesInDir(fullPath).sort{ $0 < $1 }
        guard !imgs.isEmpty else { return nil }
        let firstImg = fullPath + "/" + imgs[0]
        guard let f = self.fm.openFile(forReadingAtPath: firstImg) else { return nil }
        let data = f.readDataToEndOfFile()
        f.closeFile()
        guard data.length != 0 else { return nil }
        let thumbnail = calcMD5(data) + ".jpg"
        let img = generateThumbnail(UIImage(data: data)!, bounds: CGSize(width: 256, height: 256))
        UIImageJPEGRepresentation(img, 0.7)?.writeToURL(documentURL.URLByAppendingPathComponent(thumbnail), atomically: true)
        return ComicRecord(context: context, server: server, title: dirName, thumbnail: thumbnail, path: path, images: imgs)
    }

    // MARK: - Segues

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "showComic" {
            if let indexPath = self.tableView.indexPathForSelectedRow {
                let controller = segue.destinationViewController as! ReaderViewController
                controller.comic = comicFetchs.objectAtIndexPath(indexPath) as! ComicRecord
            }
        }
        if segue.identifier == "showComicChooser" {
            let controller = segue.destinationViewController as! ChooserViewController
            controller.chooseCompletion = { ret in
                let (server, path) = ret
                SVProgressHUD.showWithMaskType(.Gradient)
                dispatch_async(smbWorkQueue, { [unowned self] in
                    let moc = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
                    moc.parentContext = self.managedObjectContext
                    self.addComicAtPath(moc, server: server, path: path)

                    do {
                        try moc.save()
                    } catch {
                        fatalError("Can not save comic records")
                    }
                    dispatch_async(dispatch_get_main_queue(), {
                        SVProgressHUD.dismiss()
                    })
                })
            }
        }
    }

    private func showAlertErrorDialog(msg: String) {
        let alertController = UIAlertController(title: "Error", message: msg, preferredStyle: .Alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
        self.presentViewController(alertController, animated: true, completion: nil)
    }

    // MARK: - Table View

    override func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        let comic = comicFetchs.objectAtIndexPath(indexPath) as! ComicRecord
        let srv = comic.server!

        SVProgressHUD.showWithMaskType(.Gradient)
        dispatch_async(smbWorkQueue) {
            let ss = SMBClient.sharedInstance
            if !ss.isConnected(srv.name, withUser: srv.username) {
                if ss.isConnected(srv.name) {
                    ss.disconnect(srv.name)
                }
                guard ss.connect(srv.name, ip: srv.ip, username: srv.username, password: srv.password) else {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.tableView.deselectRowAtIndexPath(indexPath, animated: false)
                        self.showAlertErrorDialog("Can not connect server!")
                    }
                    return
                }
            }
            dispatch_async(dispatch_get_main_queue()) {
                SVProgressHUD.dismiss()
                self.performSegueWithIdentifier("showComic", sender: nil)
            }
        }
        return indexPath
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sections = comicFetchs.sections
        return sections![section].numberOfObjects
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! LibraryCell
        let comic = comicFetchs.objectAtIndexPath(indexPath) as! ComicRecord

        cell.titleLabel.text = comic.title
        let fileUrl = documentURL.URLByAppendingPathComponent(comic.thumbnail!)
        let img = UIImage(contentsOfFile: fileUrl.path!)!
        cell.thumbnailImg.image = img
        cell.progressLabel.text = "\(comic.cur!) / \(comic.images!.count)"
        let ratio = min(178.0 / img.size.width, 178.0 / img.size.height)
        cell.widthContraint.constant = img.size.width * ratio
        cell.heightContraint.constant = img.size.height * ratio

        return cell
    }

    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            let comic = comicFetchs.objectAtIndexPath(indexPath) as! ComicRecord
            try! NSFileManager.defaultManager().removeItemAtURL(documentURL.URLByAppendingPathComponent(comic.thumbnail!))
            managedObjectContext.deleteObject(comic)
        } else if editingStyle == .Insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
        }
    }

    // MARK: - Fetch Controller
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        tableView.beginUpdates()
    }

    func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch type {
        case .Insert:
            tableView.insertRowsAtIndexPaths([newIndexPath!], withRowAnimation: .Fade)
        case .Delete:
            tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Fade)
        case .Update:
            let comic = anObject as! ComicRecord
            let cell = tableView.cellForRowAtIndexPath(indexPath!) as! LibraryCell
            cell.progressLabel.text = "\(comic.cur!) / \(comic.images!.count)"
        case .Move:
            //tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Fade)
            //tableView.insertRowsAtIndexPaths([indexPath!], withRowAnimation: .Fade)
            print("move \(indexPath) \(newIndexPath)")
        }
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        tableView.endUpdates()
    }
}
