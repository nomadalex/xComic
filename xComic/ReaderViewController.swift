//
//  ReaderViewController.swift
//  xComic
//
//  Created by Kun Wang on 4/27/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import UIKit
import PINCache

class ReaderCell: UITableViewCell {
    @IBOutlet var contentImage: UIImageView!
    @IBOutlet var widthConstraint: NSLayoutConstraint!
    @IBOutlet var heightConstraint: NSLayoutConstraint!
}

class ReaderViewController: UITableViewController {
    private let leftZoneRatio: CGFloat = 0.3
    private let rightZoneRatio: CGFloat = 0.3

    var comic: ComicRecord!

    private var isShowTop = false
    private let fm = SMBFileManager.sharedInstance

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        navigationController!.navigationBarHidden = !isShowTop
        title = comic.title!

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Goto", style: .Plain, target: self, action: #selector(showGotoPageDialog))

        tableView.transform = CGAffineTransformMakeRotation(-CGFloat(M_PI_2))
        tableView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 0, tableView.bounds.height - 7)
    }

    override func prefersStatusBarHidden() -> Bool {
        return !isShowTop
    }

    override func preferredStatusBarUpdateAnimation() -> UIStatusBarAnimation {
        return .Slide
    }

    private func getCurrentPage() -> Int {
        let offset = tableView.contentOffset
        let cur = Int(offset.y / tableView.bounds.height)
        return cur + 1
    }

    @IBAction func tapOnTableView(sender: AnyObject) {
        let g = sender as! UIGestureRecognizer
        let bounds = g.view!.bounds
        var pt = g.locationInView(g.view)
        pt.y -= tableView.contentOffset.y
        if pt.y <= bounds.height * leftZoneRatio {
            let cur = getCurrentPage()
            if cur > 1 {
                tableView.contentOffset = CGPoint(x: 0, y: CGFloat(cur-2) * tableView.bounds.height)
            }
        } else if pt.y >= bounds.height * (1 - rightZoneRatio) {
            let cur = getCurrentPage()
            if cur < comic.images!.count {
                tableView.contentOffset = CGPoint(x: 0, y: CGFloat(cur) * tableView.bounds.height)
            }
        } else {
            isShowTop = !isShowTop
            setNeedsStatusBarAppearanceUpdate()
            navigationController!.setNavigationBarHidden(!isShowTop, animated: true)
        }
    }

    override func viewWillAppear(animated: Bool) {
        let cur = comic.cur! as Int
        // delay it because the transform not apply now
        dispatch_async(dispatch_get_main_queue()) {
            self.tableView.contentOffset = CGPoint(x: 0, y: CGFloat(cur-1) * self.tableView.bounds.height)
        }
    }

    override func viewWillDisappear(animated: Bool) {
        comic.cur = getCurrentPage()
    }

    func showGotoPageDialog(sender: AnyObject) {
        let controller = UIAlertController(title: "Goto", message: nil, preferredStyle: .Alert)

        let okAction = UIAlertAction(title: "OK", style: .Default) { _ in
            let pageTextField = controller.textFields![0] as UITextField

            guard let page = Int(pageTextField.text!) else { return }
            self.gotoPage(page)
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: nil)

        controller.addTextFieldWithConfigurationHandler { textField in
            textField.placeholder = self.comic.images!.count.description

            NSNotificationCenter.defaultCenter().addObserverForName(UITextFieldTextDidChangeNotification, object: textField, queue: NSOperationQueue.mainQueue()) { _ in
                guard let page = Int(textField.text!) else {
                    okAction.enabled = false
                    return
                }
                okAction.enabled = 1...self.comic.images!.count ~= page
            }
        }

        controller.addAction(okAction)
        controller.addAction(cancelAction)

        presentViewController(controller, animated: true, completion: nil)
    }

    private func gotoPage(page: Int) {
        comic.cur = page
        tableView.contentOffset = CGPoint(x: 0, y: CGFloat(page-1) * tableView.frame.width)
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
        return tableView.frame.width
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! ReaderCell

        cell.transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))

        weak var weakCell = cell
        func setContentAsync(img: UIImage) {
            dispatch_async(dispatch_get_main_queue()) {
                if let cell = weakCell {
                    cell.contentImage.image = img
                    let cellSize = cell.contentView.frame.size
                    let ratio = min(cellSize.width / img.size.width, cellSize.height / img.size.height)
                    cell.widthConstraint.constant = img.size.width * ratio
                    cell.heightConstraint.constant = img.size.height * ratio
                }
            }
        }

        let img = UIImage.gifWithName("placeholder")
        cell.contentImage.image = img
        cell.widthConstraint.constant = img!.size.width
        cell.heightConstraint.constant = img!.size.height

        let path = getComicImageFullPath(indexPath.row)
        let cacheKey = "smb:" + path

        PINCache.sharedCache().objectForKey(cacheKey) { _, key, obj in
            if let img = obj {
                setContentAsync(img as! UIImage)
            } else {
                dispatch_async(smbWorkQueue) {
                    guard let f = self.fm.openFile(forReadingAtPath: path) else { return }
                    let data = f.readDataToEndOfFile()
                    f.closeFile()
                    guard let img = UIImage(data: data) else { return }
                    PINCache.sharedCache().setObject(img, forKey: key, block: nil)
                    setContentAsync(img)
                }
            }
        }

        return cell
    }
}