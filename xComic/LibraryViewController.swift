//
//  LibraryViewController.swift
//  xComic
//
//  Created by Kun Wang on 4/25/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import UIKit

class LibraryCell: UITableViewCell {
    @IBOutlet
    var thumbnailImg: UIImageView!
    @IBOutlet
    var titleLabel: UILabel!
    @IBOutlet
    var progressLabel: UILabel!
}

struct Comic {
    let thumbnail: String
    let title: String
    var cur: Int
    let total: Int
}

class LibraryViewController: UITableViewController {

    private var comics = [Comic]()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.navigationItem.leftBarButtonItem = self.editButtonItem()

        let addButton = UIBarButtonItem(barButtonSystemItem: .Add, target: self, action: #selector(addComic(_:)))
        self.navigationItem.rightBarButtonItem = addButton
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func addComic(sender: AnyObject) {
        self.comics.insert(Comic(thumbnail: "", title: NSDate().description, cur: 0, total: 10), atIndex: 0)
        let indexPath = NSIndexPath(forRow: 0, inSection: 0)
        self.tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
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
    }

    // MARK: - Table View

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return comics.count
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! LibraryCell
        let comic = self.comics[indexPath.row]

        cell.titleLabel.text = comic.title
        cell.progressLabel.text = "\(comic.cur) / \(comic.total)"

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