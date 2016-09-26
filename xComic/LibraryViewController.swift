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

let smbWorkQueue = DispatchQueue(label: "com.ifreedomlife.xComic", attributes: [])

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

    fileprivate let fm = SMBFileManager.sharedInstance

    var documentURL: URL!
    var managedObjectContext: NSManagedObjectContext!

    fileprivate var comicFetchs: NSFetchedResultsController<ComicRecord>!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.navigationItem.leftBarButtonItem = self.editButtonItem

        let optionButton = UIBarButtonItem(title: "Option", style: .plain, target: self, action: #selector(showOptionMenu))
        self.navigationItem.rightBarButtonItem = optionButton

        initComicFetchs()
    }

    fileprivate func initComicFetchs() {
        let request = NSFetchRequest<ComicRecord>(entityName: "ComicRecord")
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

    func showOptionMenu(_ sender: AnyObject) {
        let menu = UIAlertController(title: nil, message: "Choose Option", preferredStyle: .actionSheet)

        menu.addAction(UIAlertAction(title: "Add", style: .default, handler: showChooser))
        menu.addAction(UIAlertAction(title: "Clear Cache", style: .default, handler: clearCache))
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let con = menu.popoverPresentationController {
            con.barButtonItem = sender as? UIBarButtonItem
        }
        self.present(menu, animated: true, completion: nil)
    }

    func showChooser(_ sender: AnyObject) {
        self.performSegue(withIdentifier: "showComicChooser", sender: nil)
    }

    func clearCache(_ sender: AnyObject) {
        PINCache.shared().removeAllObjects()
    }

    fileprivate func calcMD5(_ data: Data) -> String {
        let digestLen = Int(CC_MD5_DIGEST_LENGTH)
        let result = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: digestLen)

        CC_MD5((data as NSData).bytes, UInt32(data.count), result)

        let hash = NSMutableString()
        for i in 0..<digestLen {
            hash.appendFormat("%02x", result[i])
        }

        result.deallocate(capacity: digestLen)
        
        return String(format: hash as String)
    }
    
    fileprivate func getImagesInDir(_ path: String) -> [String] {
        let imgs = fm.contentsOfDirectoryAtPath(path).filter { fn in
            guard fn[fn.startIndex] != "." else { return false }
            let ext = (fn as NSString).pathExtension
            switch ext.lowercased() {
            case "jpg", "jpeg", "png": return true
            default: return false
            }
        }
        return imgs
    }

    fileprivate func generateThumbnail(_ img: UIImage, bounds: CGSize) -> UIImage {
        let horiRatio = bounds.width / img.size.width
        let vertRatio = bounds.height / img.size.height
        let ratio = min(horiRatio, vertRatio)
        let newSize = CGSize(width: img.size.width * ratio, height: img.size.height * ratio)

        UIGraphicsBeginImageContext(newSize)
        img.draw(in: CGRect(origin: CGPoint.zero, size: newSize))
        let newImg = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImg!
    }

    fileprivate func addComicAtPath(_ context: NSManagedObjectContext, server: ServerEntry, path: String) -> ComicRecord? {
        let dirName = (path as NSString).lastPathComponent
        let fullPath = "/\(server.name)/\(path)"
        let imgs = getImagesInDir(fullPath).sorted{ $0 < $1 }
        guard !imgs.isEmpty else { return nil }
        let firstImg = fullPath + "/" + imgs[0]
        guard let f = self.fm.openFile(forReadingAtPath: firstImg) else { return nil }
        let data = f.readDataToEndOfFile()
        f.closeFile()
        guard data.count != 0 else { return nil }
        let thumbnail = calcMD5(data) + ".jpg"
        let img = generateThumbnail(UIImage(data: data)!, bounds: CGSize(width: 256, height: 256))
        try! UIImageJPEGRepresentation(img, 0.7)?.write(to: documentURL.appendingPathComponent(thumbnail), options: .atomic)
        return ComicRecord(context: context, server: server, title: dirName, thumbnail: thumbnail, path: path, images: imgs)
    }

    // MARK: - Segues

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showComic" {
            if let indexPath = self.tableView.indexPathForSelectedRow {
                let controller = segue.destination as! ReaderViewController
                controller.comic = comicFetchs.object(at: indexPath)
            }
        }
        if segue.identifier == "showComicChooser" {
            let controller = segue.destination as! ChooserViewController
            controller.chooseCompletion = { ret in
                let (server, path) = ret
                SVProgressHUD.show(with: .gradient)
                smbWorkQueue.async(execute: { [unowned self] in
                    let moc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                    moc.parent = self.managedObjectContext
                    _ = self.addComicAtPath(moc, server: server, path: path)

                    do {
                        try moc.save()
                    } catch {
                        fatalError("Can not save comic records")
                    }
                    DispatchQueue.main.async(execute: {
                        SVProgressHUD.dismiss()
                    })
                })
            }
        }
    }

    fileprivate func showAlertErrorDialog(_ msg: String) {
        let alertController = UIAlertController(title: "Error", message: msg, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alertController, animated: true, completion: nil)
    }

    // MARK: - Table View

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let comic = comicFetchs.object(at: indexPath) 
        let srv = comic.server!

        SVProgressHUD.show(with: .gradient)
        smbWorkQueue.async {
            let ss = SMBClient.sharedInstance
            if !ss.isConnected(srv.name, withUser: srv.username) {
                if ss.isConnected(srv.name) {
                    ss.disconnect(srv.name)
                }
                guard ss.connect(srv.name, ip: srv.ip, username: srv.username, password: srv.password) else {
                    DispatchQueue.main.async {
                        self.tableView.deselectRow(at: indexPath, animated: false)
                        self.showAlertErrorDialog("Can not connect server!")
                    }
                    return
                }
            }
            DispatchQueue.main.async {
                SVProgressHUD.dismiss()
                self.performSegue(withIdentifier: "showComic", sender: nil)
            }
        }
        return indexPath
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sections = comicFetchs.sections
        return sections![section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! LibraryCell
        let comic = comicFetchs.object(at: indexPath) 

        cell.titleLabel.text = comic.title
        let fileUrl = documentURL.appendingPathComponent(comic.thumbnail!)
        let img = UIImage(contentsOfFile: fileUrl.path)!
        cell.thumbnailImg.image = img
        cell.progressLabel.text = "\(comic.cur!) / \(comic.images!.count)"
        let ratio = min(178.0 / img.size.width, 178.0 / img.size.height)
        cell.widthContraint.constant = img.size.width * ratio
        cell.heightContraint.constant = img.size.height * ratio

        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let comic = comicFetchs.object(at: indexPath) 
            try! FileManager.default.removeItem(at: documentURL.appendingPathComponent(comic.thumbnail!))
            managedObjectContext.delete(comic)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
        }
    }

    // MARK: - Fetch Controller
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            tableView.insertRows(at: [newIndexPath!], with: .fade)
        case .delete:
            tableView.deleteRows(at: [indexPath!], with: .fade)
        case .update:
            let comic = anObject as! ComicRecord
            let cell = tableView.cellForRow(at: indexPath!) as! LibraryCell
            cell.progressLabel.text = "\(comic.cur!) / \(comic.images!.count)"
        case .move:
            //tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Fade)
            //tableView.insertRowsAtIndexPaths([indexPath!], withRowAnimation: .Fade)
            print("move \(indexPath) \(newIndexPath)")
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
}
