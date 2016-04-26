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

class LibraryCell: UITableViewCell {
    @IBOutlet
    var thumbnailImg: UIImageView!
    @IBOutlet
    var titleLabel: UILabel!
    @IBOutlet
    var progressLabel: UILabel!
}

struct Comic {
    let title: String
    let images: [String]
    var cur: Int
}

class LibraryViewController: UITableViewController {

    private let fm = SMBFileManager.sharedInstance

    private var comics = [Comic]()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.navigationItem.leftBarButtonItem = self.editButtonItem()

        let optionButton = UIBarButtonItem(title: "Option", style: .Plain, target: self, action: #selector(showOptionMenu))
        self.navigationItem.rightBarButtonItem = optionButton
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func showOptionMenu(sender: AnyObject) {
        let menu = UIAlertController(title: nil, message: "Choose Option", preferredStyle: .ActionSheet)

        menu.addAction(UIAlertAction(title: "Add", style: .Default, handler: showChooser))
        menu.addAction(UIAlertAction(title: "Settings", style: .Default, handler: nil))
        menu.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))

        menu.popoverPresentationController!.barButtonItem = sender as? UIBarButtonItem
        self.presentViewController(menu, animated: true, completion: nil)
    }

    func showChooser(sender: AnyObject) {
        self.performSegueWithIdentifier("showComicChooser", sender: nil)
    }

    private func getImagesInDir(path: String) -> [String] {
        let imgs = fm.contentsOfDirectoryAtPath(path).filter { fn in
                let ext = (fn as NSString).pathExtension
                switch ext.lowercaseString {
                case "jpg", "jpeg", "png": return true
                default: return false
                }
            }
        return imgs
    }

    private func addComicAtPath(path: String) {
        let imgs = getImagesInDir(path).map { fn in path + "/" + fn }
        guard !imgs.isEmpty else { return }
        let dirName = (path as NSString).lastPathComponent
        self.comics.append(Comic(title: dirName, images: imgs, cur: 0))
    }

    // MARK: - Segues

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        /*
        if segue.identifier == "showDetail" {
            if let indexPath = self.tableView.indexPathForSelectedRow {
                let controller = (segue.destinationViewController as! UINavigationController).topViewController as! DetailViewController
                controller.detailItem = objects[indexPath.row]
                controller.navigationItem.leftBarButtonItem = self.splitViewController?.displayModeButtonItem()
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
        }
         */
        if segue.identifier == "showComicChooser" {
            let controller = segue.destinationViewController as! ChooserViewController
            controller.chooseCompletion = { paths in
                SVProgressHUD.showWithMaskType(.Gradient)
                let lastCount = self.comics.count
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
                    for path in paths {
                        self.addComicAtPath("/" + path.0 + "/" + path.1)
                    }
                    dispatch_async(dispatch_get_main_queue(), {
                        SVProgressHUD.dismiss()
                        guard lastCount < self.comics.count else { return }
                        let indexs = (lastCount..<self.comics.count).map() { i in NSIndexPath(forRow: i, inSection: 0) }
                        self.tableView.insertRowsAtIndexPaths(indexs, withRowAnimation: .Automatic)
                    })
                })
            }
        }
    }

    // MARK: - Table View

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return comics.count
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! LibraryCell
        let comic = self.comics[indexPath.row]

        weak var weakCell = cell
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)) {
            guard let f = self.fm.openFile(forReadingAtPath: comic.images[0]) else { return }
            let data = f.readDataToEndOfFile()
            f.closeFile()

            dispatch_async(dispatch_get_main_queue()) {
                if let cell = weakCell {
                    cell.thumbnailImg.image = UIImage(data: data)
                }
            }
        }

        cell.titleLabel.text = comic.title
        cell.progressLabel.text = "\(comic.cur) / \(comic.images.count)"

        return cell
    }

    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            self.comics.removeAtIndex(indexPath.row)
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
        } else if editingStyle == .Insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
        }
    }
}