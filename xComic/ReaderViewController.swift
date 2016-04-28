//
//  ReaderViewController.swift
//  xComic
//
//  Created by Kun Wang on 4/27/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import UIKit

class ReaderCell: UITableViewCell {
    @IBOutlet var contentImage: UIImageView!
    @IBOutlet var widthConstraint: NSLayoutConstraint!
    @IBOutlet var heightConstraint: NSLayoutConstraint!
}

class ReaderViewController: UITableViewController {
    var comic: ComicRecord!

    private var isShowTop = false
    private let fm = SMBFileManager.sharedInstance

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        navigationController!.navigationBarHidden = !isShowTop
        title = comic.title!
    }

    override func prefersStatusBarHidden() -> Bool {
        return !isShowTop
    }

    override func preferredStatusBarUpdateAnimation() -> UIStatusBarAnimation {
        return .Slide
    }

    @IBAction func toggleTopDisplay(sender: AnyObject) {
        isShowTop = !isShowTop
        setNeedsStatusBarAppearanceUpdate()
        navigationController!.setNavigationBarHidden(!isShowTop, animated: true)
    }

    private func getComicImageFullPath(idx: Int) -> String {
        let srvName = comic.server!.name
        let dir = comic.path!
        let fn = comic.images![idx]
        return "/\(srvName)/\(dir)/\(fn)"
    }

    // MARK: - Table View

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return comic.images!.count
    }

    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return tableView.frame.height
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! ReaderCell

        let img = UIImage.gifWithName("placeholder")
        cell.contentImage.image = img
        cell.widthConstraint.constant = img!.size.width
        cell.heightConstraint.constant = img!.size.height

        weak var weakCell = cell
        let idx = indexPath.row
        let path = getComicImageFullPath(idx)
        dispatch_async(smbWorkQueue) {
            guard let f = self.fm.openFile(forReadingAtPath: path) else { return }
            let data = f.readDataToEndOfFile()
            f.closeFile()

            dispatch_async(dispatch_get_main_queue()) {
                if let cell = weakCell {
                    guard let img = UIImage(data: data) else { return }
                    cell.contentImage.image = img
                    let cellSize = cell.contentView.frame.size
                    let ratio = min(cellSize.width / img.size.width, cellSize.height / img.size.height)
                    cell.widthConstraint.constant = img.size.width * ratio
                    cell.heightConstraint.constant = img.size.height * ratio
                }
            }
        }

        return cell
    }
}