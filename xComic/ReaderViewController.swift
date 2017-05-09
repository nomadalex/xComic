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
    fileprivate let leftZoneRatio: CGFloat = 0.3
    fileprivate let rightZoneRatio: CGFloat = 0.3

    var comic: ComicRecord!

    fileprivate var isShowTop = false
    fileprivate let fm = SMBFileManager.sharedInstance

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        navigationController!.isNavigationBarHidden = !isShowTop
        title = comic.title!

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Goto", style: .plain, target: self, action: #selector(showGotoPageDialog))

        tableView.transform = CGAffineTransform(rotationAngle: -CGFloat(Float.pi/2))
        tableView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 0, tableView.bounds.height - 7)
    }

    override var prefersStatusBarHidden : Bool {
        return !isShowTop
    }

    override var preferredStatusBarUpdateAnimation : UIStatusBarAnimation {
        return .slide
    }

    fileprivate func getCurrentPage() -> Int {
        let offset = tableView.contentOffset
        let cur = Int(offset.y / tableView.bounds.height)
        return cur + 1
    }

    @IBAction func tapOnTableView(_ sender: AnyObject) {
        let g = sender as! UIGestureRecognizer
        let bounds = g.view!.bounds
        var pt = g.location(in: g.view)
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

    override func viewWillAppear(_ animated: Bool) {
        let cur = comic.cur! as! Int
        // delay it because the transform not apply now
        DispatchQueue.main.async {
            self.tableView.contentOffset = CGPoint(x: 0, y: CGFloat(cur-1) * self.tableView.bounds.height)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        comic.cur = getCurrentPage() as NSNumber?
    }

    func showGotoPageDialog(_ sender: AnyObject) {
        let controller = UIAlertController(title: "Goto", message: nil, preferredStyle: .alert)

        let okAction = UIAlertAction(title: "OK", style: .default) { _ in
            let pageTextField = controller.textFields![0] as UITextField

            guard let page = Int(pageTextField.text!) else { return }
            self.gotoPage(page)
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        controller.addTextField { textField in
            textField.placeholder = self.comic.images!.count.description

            NotificationCenter.default.addObserver(forName: NSNotification.Name.UITextFieldTextDidChange, object: textField, queue: OperationQueue.main) { _ in
                guard let page = Int(textField.text!) else {
                    okAction.isEnabled = false
                    return
                }
                okAction.isEnabled = 1...self.comic.images!.count ~= page
            }
        }

        controller.addAction(okAction)
        controller.addAction(cancelAction)

        present(controller, animated: true, completion: nil)
    }

    fileprivate func gotoPage(_ page: Int) {
        comic.cur = page as NSNumber?
        tableView.contentOffset = CGPoint(x: 0, y: CGFloat(page-1) * tableView.frame.width)
    }

    fileprivate func getComicImageFullPath(_ idx: Int) -> String {
        let srvName = comic.server!.name
        let dir = comic.path!
        let fn = comic.images![idx]
        return "/\(srvName)/\(dir)/\(fn)"
    }

    // MARK: - Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return comic.images!.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return tableView.frame.width
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! ReaderCell

        cell.transform = CGAffineTransform(rotationAngle: CGFloat(Float.pi/2))

        weak var weakCell = cell
        func setContentAsync(_ img: UIImage) {
            DispatchQueue.main.async {
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

        let path = getComicImageFullPath((indexPath as NSIndexPath).row)
        let cacheKey = "smb:" + path

        PINCache.shared().object(forKey: cacheKey) { _, key, obj in
            if let img = obj {
                setContentAsync(img as! UIImage)
            } else {
                smbWorkQueue.async {
                    guard let f = self.fm.openFile(forReadingAtPath: path) else { return }
                    let data = f.readDataToEndOfFile()
                    f.closeFile()
                    guard let img = UIImage(data: data) else { return }
                    PINCache.shared().setObject(img, forKey: key, block: nil)
                    setContentAsync(img)
                }
            }
        }

        return cell
    }
}
