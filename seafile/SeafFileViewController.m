//
//  SeafMasterViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//
#import <MWPhotoBrowser.h>

#import "SeafAppDelegate.h"
#import "SeafFileViewController.h"
#import "SeafDetailViewController.h"
#import "SeafUploadDirViewController.h"
#import "SeafDirViewController.h"
#import "SeafFile.h"
#import "SeafRepos.h"
#import "SeafCell.h"
#import "SeafUploadingFileCell.h"
#import "SeafPhoto.h"
#import "SeafThumb.h"

#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "Debug.h"

#import "QBImagePickerController.h"

enum {
    STATE_INIT = 0,
    STATE_LOADING,
    STATE_DELETE,
    STATE_MKDIR,
    STATE_CREATE,
    STATE_RENAME,
    STATE_PASSWORD,
    STATE_MOVE,
    STATE_COPY,
    STATE_SHARE_EMAIL,
    STATE_SHARE_LINK,
};


@interface SeafFileViewController ()<QBImagePickerControllerDelegate, UIPopoverControllerDelegate, SeafUploadDelegate, EGORefreshTableHeaderDelegate, SeafDirDelegate, SeafShareDelegate, SeafRepoPasswordDelegate, UISearchBarDelegate, UISearchDisplayDelegate, UIActionSheetDelegate, MFMailComposeViewControllerDelegate, SWTableViewCellDelegate, MWPhotoBrowserDelegate>
- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView;

@property (strong, nonatomic) SeafDir *directory;
@property (strong) id<SeafItem> curEntry;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@property (strong) UIBarButtonItem *selectAllItem;
@property (strong) UIBarButtonItem *selectNoneItem;
@property (strong) UIBarButtonItem *photoItem;
@property (strong) UIBarButtonItem *doneItem;
@property (strong) UIBarButtonItem *editItem;
@property (strong) NSArray *rightItems;

@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;

@property (retain) SWTableViewCell *selectedCell;
@property (retain) NSIndexPath *selectedindex;
@property (readonly) NSArray *editToolItems;

@property (strong) UIActionSheet *actionSheet;

@property int state;

@property(nonatomic,strong) UIPopoverController *popoverController;
@property (retain) NSDateFormatter *formatter;

@property(nonatomic, strong, readwrite) UISearchBar *searchBar;
@property(nonatomic, strong) UISearchDisplayController *strongSearchDisplayController;

@property (strong) NSMutableArray *searchResults;

@property (strong, retain) NSArray *photos;
@property (strong, retain) NSArray *thumbs;
@property BOOL inPhotoBrowser;

@end

@implementation SeafFileViewController

@synthesize connection = _connection;
@synthesize directory = _directory;
@synthesize curEntry = _curEntry;
@synthesize selectAllItem = _selectAllItem, selectNoneItem = _selectNoneItem;
@synthesize selectedindex = _selectedindex;
@synthesize selectedCell = _selectedCell;

@synthesize editToolItems = _editToolItems;

@synthesize popoverController;


- (SeafDetailViewController *)detailViewController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return (SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SEAFILE];
}

- (NSArray *)editToolItems
{
    if (!_editToolItems) {
        int i;
        UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
        UIBarButtonItem *fixedSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:self action:nil];

        NSArray *itemsTitles = [NSArray arrayWithObjects:S_MKDIR, S_NEWFILE, NSLocalizedString(@"Copy", @"Seafile"), NSLocalizedString(@"Move", @"Seafile"), S_DELETE, NSLocalizedString(@"PasteTo", @"Seafile"), NSLocalizedString(@"MoveTo", @"Seafile"), STR_CANCEL, nil ];

        UIBarButtonItem *items[EDITOP_NUM];
        items[0] = flexibleFpaceItem;

        fixedSpaceItem.width = 38.0f;;
        for (i = 1; i < itemsTitles.count + 1; ++i) {
            items[i] = [[UIBarButtonItem alloc] initWithTitle:[itemsTitles objectAtIndex:i-1] style:UIBarButtonItemStyleBordered target:self action:@selector(editOperation:)];
            items[i].tag = i;
        }

        _editToolItems = [NSArray arrayWithObjects:items[EDITOP_COPY], items[EDITOP_MOVE], items[EDITOP_SPACE], items[EDITOP_DELETE], nil ];
    }
    return _editToolItems;
}

- (void)setConnection:(SeafConnection *)conn
{
    self.searchDisplayController.active = NO;
    [self.detailViewController setPreViewItem:nil master:nil];
    [conn loadRepos:self];
    [self setDirectory:(SeafDir *)conn.rootFolder];
}

- (void)showLodingView
{
    if (!self.loadingView) {
        self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        self.loadingView.color = [UIColor darkTextColor];
        self.loadingView.hidesWhenStopped = YES;
        [self.view addSubview:self.loadingView];
    }
    self.loadingView.center = self.view.center;
    [self.loadingView startAnimating];
}

- (void)dismissLoadingView
{
    [self.loadingView stopAnimating];
}

- (void)awakeFromNib
{
    if (IsIpad()) {
        self.preferredContentSize = CGSizeMake(320.0, 600.0);
    }
    [super awakeFromNib];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    self.formatter = [[NSDateFormatter alloc] init];
    [self.formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];
    self.tableView.rowHeight = 50;

    self.state = STATE_INIT;
    _refreshHeaderView = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
    _refreshHeaderView.delegate = self;
    [_refreshHeaderView refreshLastUpdatedDate];
    [self.tableView addSubview:_refreshHeaderView];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.searchTextPositionAdjustment = UIOffsetMake(0, 0);
    self.searchBar.placeholder = NSLocalizedString(@"Search", @"Seafile");
    self.searchBar.delegate = self;
    [self.searchBar sizeToFit];
    self.strongSearchDisplayController = [[UISearchDisplayController alloc] initWithSearchBar:self.searchBar contentsController:self];
    self.searchDisplayController.searchResultsDataSource = self;
    self.searchDisplayController.searchResultsDelegate = self;
    self.searchDisplayController.delegate = self;
    self.tableView.tableHeaderView = self.searchBar;
    self.tableView.contentOffset = CGPointMake(0, CGRectGetHeight(self.searchBar.bounds));
    self.tableView.allowsMultipleSelection = NO;

    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    [self.navigationController setToolbarHidden:YES animated:NO];
}

- (void)noneSelected:(BOOL)none
{
    if (none) {
        self.navigationItem.leftBarButtonItem = _selectAllItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:NO];
        [[items objectAtIndex:1] setEnabled:NO];
        [[items objectAtIndex:3] setEnabled:NO];
    } else {
        self.navigationItem.leftBarButtonItem = _selectNoneItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:YES];
        [[items objectAtIndex:1] setEnabled:YES];
        [[items objectAtIndex:3] setEnabled:YES];
    }
}

- (void)checkPreviewFileExist
{
    if ([self.detailViewController.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)self.detailViewController.preViewItem;
        NSString *parent = [sfile.path stringByDeletingLastPathComponent];
        BOOL deleted = YES;
        if (![_directory isKindOfClass:[SeafRepos class]] && _directory.repoId == sfile.repoId && [parent isEqualToString:_directory.path]) {
            for (SeafBase *entry in _directory.allItems) {
                if (entry == sfile) {
                    deleted = NO;
                    break;
                }
            }
            if (deleted)
                [self.detailViewController setPreViewItem:nil master:nil];
        }
    }
}

- (void)initSeafPhotos
{
    NSMutableArray *seafPhotos = [[NSMutableArray alloc] init];
    NSMutableArray *seafThumbs = [[NSMutableArray alloc] init];

    for (id entry in _directory.allItems) {
        if ([entry conformsToProtocol:@protocol(SeafPreView)]
            && [(id<SeafPreView>)entry isImageFile]) {
            id<SeafPreView> file = entry;
            [file setDelegate:self];
            [seafPhotos addObject:[[SeafPhoto alloc] initWithSeafPreviewIem:entry]];
            [seafThumbs addObject:[[SeafThumb alloc] initWithSeafPreviewIem:entry]];
        }
    }
    self.photos = seafPhotos;
    self.thumbs = seafThumbs;
}

- (void)refreshView
{
    [self initSeafPhotos];
    for (SeafUploadFile *file in _directory.uploadItems) {
        file.delegate = self;
    }
    [self.tableView reloadData];
    if (IsIpad() && self.detailViewController.preViewItem) {
        [self checkPreviewFileExist];
    }
    if (self.editing) {
        if (![self.tableView indexPathsForSelectedRows])
            [self noneSelected:YES];
        else
            [self noneSelected:NO];
    }
    if (!_directory.hasCache) {
        Debug("no cache, load from server.");
        [self showLodingView];
        self.state = STATE_LOADING;
    }
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    [self setLoadingView:nil];
    _refreshHeaderView = nil;
    _directory = nil;
    _curEntry = nil;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    if (!self.isVisible)
        [_directory unload];
}

- (void)selectAll:(id)sender
{
    int row;
    long count = _directory.allItems.count;
    for (row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
        if (![entry isKindOfClass:[SeafUploadFile class]])
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    }
    [self noneSelected:NO];
}

- (void)selectNone:(id)sender
{
    long count = _directory.allItems.count;
    for (int row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
    [self noneSelected:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (editing) {
        if (![appdelegate checkNetworkStatus]) return;
        [self.navigationController.toolbar sizeToFit];
        [self setToolbarItems:self.editToolItems];
        [self noneSelected:YES];
        [self.photoItem setEnabled:NO];
        [self.navigationController setToolbarHidden:NO animated:YES];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        [self.navigationController setToolbarHidden:YES animated:YES];
        //if(!IsIpad())  self.tabBarController.tabBar.hidden = NO;
        [self.photoItem setEnabled:YES];
    }

    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

- (void)addPhotos:(id)sender
{
    if(self.popoverController)
        return;
    if (![QBImagePickerController isAccessible]) {
        Warning("Error: Source is not accessible.");
        [self alertWithTitle:NSLocalizedString(@"Photos are not accessible", @"Seafile")];
        return;
    }
    QBImagePickerController *imagePickerController = [[QBImagePickerController alloc] init];
    imagePickerController.title = NSLocalizedString(@"Photos", @"Seafile");
    imagePickerController.delegate = self;
    imagePickerController.allowsMultipleSelection = YES;
    imagePickerController.filterType = QBImagePickerControllerFilterTypeNone;

    if (IsIpad()) {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:imagePickerController];
        self.popoverController = [[UIPopoverController alloc] initWithContentViewController:navigationController];
        self.popoverController.delegate = self;
        [self.popoverController presentPopoverFromBarButtonItem:self.photoItem permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate showDetailView:imagePickerController];
    }
}

- (void)editDone:(id)sender
{
    [self setEditing:NO animated:YES];
    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.rightBarButtonItems = self.rightItems;
}

- (void)editStart:(id)sender
{
    [self setEditing:YES animated:YES];
    if (self.editing) {
        self.navigationItem.rightBarButtonItems = nil;
        self.navigationItem.rightBarButtonItem = self.doneItem;
        if (IsIpad() && self.popoverController) {
            [self.popoverController dismissPopoverAnimated:YES];
            self.popoverController = nil;
        }
    }
}

- (void)editSheet:(id)sender
{
    NSMutableArray *titles = nil;
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        titles = [NSMutableArray arrayWithObjects:S_SORT_NAME, S_SORT_MTIME, nil];
    } else if (_directory.editable) {
        titles = [NSMutableArray arrayWithObjects:S_DOWNLOAD, S_EDIT, S_NEWFILE, S_MKDIR, S_SORT_NAME, S_SORT_MTIME, S_PHOTOS_ALBUM, nil];
        if (self.photos.count >= 3) [titles addObject:S_PHOTOS_BROWSER];
    } else {
        titles = [NSMutableArray arrayWithObjects:S_DOWNLOAD, S_SORT_NAME, S_SORT_MTIME, S_PHOTOS_ALBUM, nil];
        if (self.photos.count >= 3) [titles addObject:S_PHOTOS_BROWSER];
    }
    [self showAlertWithAction:titles fromBarItem:self.editItem withTitle:nil];
}

- (void)initNavigationItems:(SeafDir *)directory
{
    if (![directory isKindOfClass:[SeafRepos class]] && directory.editable) {
        self.photoItem = [self getBarItem:@"plus".navItemImgName action:@selector(addPhotos:)size:20];
        self.doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(editDone:)];
        self.editItem = [self getBarItemAutoSize:@"ellipsis".navItemImgName action:@selector(editSheet:)];
        UIBarButtonItem *space = [self getSpaceBarItem:16.0];
        self.rightItems = [NSArray arrayWithObjects: self.editItem, space, self.photoItem, nil];

        _selectAllItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select All", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectAll:)];
        _selectNoneItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select None", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectNone:)];
    } else {
        self.editItem = [self getBarItemAutoSize:@"ellipsis".navItemImgName action:@selector(editSheet:)];
        self.rightItems = [NSArray arrayWithObjects: self.editItem, nil];
    }
    self.navigationItem.rightBarButtonItems = self.rightItems;
}

- (SeafDir *)directory
{
    return _directory;
}

- (void)setDirectory:(SeafDir *)directory
{
    if (!_directory)
        [self initNavigationItems:directory];

    _connection = directory->connection;
    _directory = directory;
    self.title = directory.name;
    [_directory loadContent:NO];
    Debug("%@, %@, %@, loading ... %d %@\n", _directory.repoId, _directory.name, _directory.path, _directory.hasCache, _directory.ooid);
    if (![_directory isKindOfClass:[SeafRepos class]])
        self.tableView.sectionHeaderHeight = 0;
    [_connection checkSyncDst:_directory];

    [self refreshView];
    [_directory setDelegate:self];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (self.loadingView.isAnimating) {
        CGRect viewBounds = self.view.bounds;
        self.loadingView.center = CGPointMake(CGRectGetMidX(viewBounds), CGRectGetMidY(viewBounds));
    }
}

- (void)checkUploadfiles
{
    [_connection checkSyncDst:_directory];
#if DEBUG
    if (_directory.uploadItems.count > 0)
        Debug("Upload %lu, state=%d", (unsigned long)_directory.uploadItems.count, self.state);
#endif
    dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, 1);
    dispatch_after(time, dispatch_get_main_queue(), ^(void){
        for (SeafUploadFile *file in _directory.uploadItems) {
            file.delegate = self;
            if (!file.uploaded && !file.uploading) {
                Debug("background upload %@", file.name);
                [[SeafGlobal sharedObject] addUploadTask:file];
            }
        }
        if ([self isViewLoaded])
            [_directory loadContent:true];
    });

}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self performSelectorInBackground:@selector(checkUploadfiles) withObject:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (IsIpad() && self.popoverController) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    if ([_directory hasCache])
        [SeafAppDelegate checkOpenLink:self];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView != self.tableView || ![_directory isKindOfClass:[SeafRepos class]]) {
        return 1;
    }
    return [[((SeafRepos *)_directory)repoGroups] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView != self.tableView)
        return self.searchResults.count;

    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return _directory.allItems.count;
    }
    NSArray *repos =  [[((SeafRepos *)_directory) repoGroups] objectAtIndex:section];
    return repos.count;
}

- (UITableViewCell *)getCell:(NSString *)CellIdentifier forTableView:(UITableView *)tableView
{
    SWTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    } else {
        cell.rightUtilityButtons = nil;
        cell.delegate = nil;
    }
    if (tableView == self.tableView) {
        cell.rightUtilityButtons = [self rightButtons];
        cell.delegate = self;
    }
    return cell;
}

- (UIAlertController *)generateAction:(NSArray *)arr withTitle:(NSString *)title
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *name in arr) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self handleAction:name];
        }];
        [alert addAction:action];
    }
    if (!IsIpad()){
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        }];
        [alert addAction:cancelAction];
    }
    return alert;
}

- (void)showAlertWithAction:(NSArray *)arr fromRect:(CGRect)rect inView:(UIView *)view withTitle:(NSString *)title
{
    if (ios8) {
        UIAlertController *alert = [self generateAction:arr withTitle:title];
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = rect;
        [self presentViewController:alert animated:true completion:nil];
    } else {
        if (self.actionSheet) {
            [self.actionSheet dismissWithClickedButtonIndex:-1 animated:NO];
            self.actionSheet = nil;
        }
        self.actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:actionSheetCancelTitle() destructiveButtonTitle:nil otherButtonTitles:nil];
        for (NSString *title in arr) {
            [self.actionSheet addButtonWithTitle:title];
        }
        [self.actionSheet showFromRect:rect inView:view animated:YES];
    }
}

- (void)showAlertWithAction:(NSArray *)arr fromBarItem:(UIBarButtonItem *)item withTitle:(NSString *)title
{
    if (ios8) {
        UIAlertController *alert = [self generateAction:arr withTitle:title];
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.barButtonItem = item;
        [self presentViewController:alert animated:true completion:nil];
    }  else {
        if (self.actionSheet) {
            [self.actionSheet dismissWithClickedButtonIndex:-1 animated:NO];
            self.actionSheet = nil;
        }
        self.actionSheet = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:actionSheetCancelTitle() destructiveButtonTitle:nil otherButtonTitles:nil];
        for (NSString *title in arr) {
            [self.actionSheet addButtonWithTitle:title];
        }
        [SeafAppDelegate showActionSheet:self.actionSheet fromBarButtonItem:item];
    }
}
- (void)showActionSheetForCell:(UITableViewCell *)cell
{
    id entry = [self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    if ([entry isKindOfClass:[SeafRepo class]]) {
        SeafRepo *repo = (SeafRepo *)entry;
        if (repo.encrypted)
            [self showAlertWithAction:[NSArray arrayWithObjects:S_RESET_PASSWORD, nil] fromRect:cell.frame inView:self.tableView withTitle:nil];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        [self showAlertWithAction:[NSArray arrayWithObjects:S_DELETE, S_RENAME, S_SHARE_EMAIL, S_SHARE_LINK, nil] fromRect:cell.frame inView:self.tableView withTitle:nil];
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        NSArray *titles;
        if (file.mpath)
            titles = [NSArray arrayWithObjects:S_DELETE, S_UPLOAD, S_SHARE_EMAIL, S_SHARE_LINK, nil];
        else
            titles = [NSArray arrayWithObjects:S_DELETE, S_REDOWNLOAD, S_RENAME, S_SHARE_EMAIL, S_SHARE_LINK, nil];
        [self showAlertWithAction:[NSArray arrayWithObjects:S_DELETE, S_REDOWNLOAD, S_RENAME, S_SHARE_EMAIL, S_SHARE_LINK, nil] fromRect:cell.frame inView:self.tableView withTitle:nil];
    } else if ([entry isKindOfClass:[SeafUploadFile class]]) {
        [self showAlertWithAction:[NSArray arrayWithObjects:S_DELETE, nil] fromRect:cell.frame inView:self.tableView withTitle:nil];
    }
}

- (void)showEditMenu:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (self.tableView.editing == YES)
        return;
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;

    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    _selectedindex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!_selectedindex)
        return;
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:_selectedindex];
    [self showActionSheetForCell:cell];
}

- (UITableViewCell *)getSeafUploadFileCell:(SeafUploadFile *)file forTableView:(UITableView *)tableView
{
    file.delegate = self;
    SWTableViewCell *c;
    if (file.uploading) {
        SeafUploadingFileCell *cell = (SeafUploadingFileCell *)[self getCell:@"SeafUploadingFileCell" forTableView:tableView];
        cell.nameLabel.text = file.name;
        cell.imageView.image = file.icon;
        [cell.progressView setProgress:file.uProgress * 1.0/100];
        c = cell;
    } else {
        SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
        cell.textLabel.text = file.name;
        cell.imageView.image = file.icon;
        cell.badgeLabel.text = nil;

        NSString *sizeStr = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:file.filesize ] useBaseTen:NO];
        NSDictionary *dict = [file uploadAttr];
        cell.accessoryView = nil;
        if (dict) {
            int utime = [[dict objectForKey:@"utime"] intValue];
            BOOL result = [[dict objectForKey:@"result"] boolValue];
            if (result)
                cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, Uploaded %@", @"Seafile"), sizeStr, [SeafDateFormatter stringFromLongLong:utime]];
            else {
                cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, waiting to upload", @"Seafile"), sizeStr];
            }
        } else {
            cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, waiting to upload", @"Seafile"), sizeStr];
        }
        c = cell;
    }
    return c;
}

- (void)updateCellContent:(SeafCell *)cell file:(SeafFile *)sfile
{
    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = sfile.detailText;
    cell.imageView.image = sfile.icon;
    cell.badgeLabel.text = nil;
}

- (SeafCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView
{
    [sfile loadCache];
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    [self updateCellContent:cell file:sfile];
    sfile.delegate = self;
    sfile.udelegate = self;
    return cell;
}

- (SeafCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafDirCell" forTableView:tableView];
    cell.textLabel.text = sdir.name;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = sdir.icon;
    sdir.delegate = self;
    return cell;
}

- (SeafCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    NSString *detail = [SeafDateFormatter stringFromLongLong:srepo.mtime];
    if ([SHARE_REPO isEqualToString:srepo.type]) {
        detail = [detail stringByAppendingFormat:@", %@", srepo.owner];
    }
    cell.detailTextLabel.text = detail;
    cell.imageView.image = srepo.icon;
    cell.textLabel.text = srepo.name;
    cell.badgeLabel.text = nil;
    srepo.delegate = self;
    if (tableView == self.tableView && srepo.encrypted) {
        [cell setRightUtilityButtons:[self repoButtons] WithButtonWidth:100];
    } else {
        cell.rightUtilityButtons = nil;
    }

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSObject *entry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (!entry) return [[UITableViewCell alloc] init];

    if (tableView != self.tableView) {
        return [self getSeafFileCell:(SeafFile *)entry forTableView:tableView];
    }
    if ([entry isKindOfClass:[SeafRepo class]]) {
        return [self getSeafRepoCell:(SeafRepo *)entry forTableView:tableView];
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        return [self getSeafFileCell:(SeafFile *)entry forTableView:tableView];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        return [self getSeafDirCell:(SeafDir *)entry forTableView:tableView];
    } else {
        return [self getSeafUploadFileCell:(SeafUploadFile *)entry forTableView:tableView];
    }
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView != self.tableView) return indexPath;
    NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (tableView.editing && [entry isKindOfClass:[SeafUploadFile class]])
        return nil;
    return indexPath;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView != self.tableView) return NO;
    NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:tableView];
    return ![entry isKindOfClass:[SeafUploadFile class]];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    [repo setDelegate:self];
    self.state = STATE_PASSWORD;
    [self popupInputView:NSLocalizedString(@"Password of this library", @"Seafile") placeholder:nil secure:true handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Password must not be empty", @"Seafile")handler:^{
                [self popupSetRepoPassword:repo];
            }];
            return;
        }
        if (input.length < 3 || input.length  > 100) {
            [self alertWithTitle:NSLocalizedString(@"The length of password should be between 3 and 100", @"Seafile") handler:^{
                [self popupSetRepoPassword:repo];
            }];
            return;
        }
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Checking library password ...", @"Seafile")];
        [repo setDelegate:self];
        [repo checkOrSetRepoPassword:input delegate:self];
    }];
}

- (void)popupMkdirView
{
    self.state = STATE_MKDIR;
    _directory.delegate = self;
    [self popupInputView:S_MKDIR placeholder:NSLocalizedString(@"New folder name", @"Seafile") secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Folder name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"Folder name invalid", @"Seafile")];
            return;
        }
        [_directory mkdir:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating folder ...", @"Seafile")];
    }];
}

- (void)popupCreateView
{
    self.state = STATE_CREATE;
    _directory.delegate = self;
    [self popupInputView:S_NEWFILE placeholder:NSLocalizedString(@"New file name", @"Seafile") secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"File name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"File name invalid", @"Seafile")];
            return;
        }
        [_directory createFile:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating file ...", @"Seafile")];
    }];
}

- (void)popupRenameView:(NSString *)newName
{
    self.state = STATE_RENAME;
    [self popupInputView:S_RENAME placeholder:newName secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"File name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"File name invalid", @"Seafile")];
            return;
        }
        [_directory renameFile:(SeafFile *)_curEntry newName:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Renaming file ...", @"Seafile")];
    }];
}

- (void)popupDirChooseView:(id<SeafPreView>)file
{
    UIViewController *controller = nil;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (file)
        controller = [[SeafUploadDirViewController alloc] initWithSeafConnection:_connection uploadFile:file];
    else
        controller = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:false];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    [appdelegate.tabbarController presentViewController:navController animated:YES completion:nil];
    if (IsIpad()) {
        CGRect frame = navController.view.superview.frame;
        navController.view.superview.frame = CGRectMake(frame.origin.x+frame.size.width/2-320/2, frame.origin.y+frame.size.height/2-500/2, 320, 500);
    }
}

- (SeafBase *)getDentrybyIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView
{
    if (!indexPath) return nil;
    @try {
        if (tableView != self.tableView) {
            return [self.searchResults objectAtIndex:indexPath.row];
        } else if (![_directory isKindOfClass:[SeafRepos class]])
            return [_directory.allItems objectAtIndex:[indexPath row]];
        NSArray *repos = [[((SeafRepos *)_directory)repoGroups] objectAtIndex:[indexPath section]];
        return [repos objectAtIndex:[indexPath row]];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (BOOL)isCurrentFileImage:(NSMutableArray **)imgs
{
    if (![_curEntry conformsToProtocol:@protocol(SeafPreView)])
        return NO;
    id<SeafPreView> pre = (id<SeafPreView>)_curEntry;
    if (!pre.isImageFile) return NO;

    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (id entry in _directory.allItems) {
        if ([entry conformsToProtocol:@protocol(SeafPreView)]
            && [(id<SeafPreView>)entry isImageFile])
            [arr addObject:entry];
    }
    *imgs = arr;
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.navigationController.topViewController != self)   return;
    _selectedindex = indexPath;
    if (tableView.editing == YES) {
        [self noneSelected:NO];
        return;
    }
    _curEntry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (!_curEntry) {
        [self performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
        return;
    }
    if ([_curEntry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curEntry passwordRequired]) {
        [self popupSetRepoPassword:(SeafRepo *)_curEntry];
        return;
    }
    [_curEntry setDelegate:self];
    if ([_curEntry conformsToProtocol:@protocol(SeafPreView)]) {
        if (!IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.detailViewController];
        }
        NSMutableArray *arr = nil;
        if ([self isCurrentFileImage:&arr]) {
            [self.detailViewController setPreViewPhotos:arr current:(id<SeafPreView>)_curEntry master:self];
        } else {
            id<SeafPreView> item = (id<SeafPreView>)_curEntry;
            [self.detailViewController setPreViewItem:item master:self];
        }
    } else if ([_curEntry isKindOfClass:[SeafDir class]]) {
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [controller setDirectory:(SeafDir *)_curEntry];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    [self tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView.editing == YES) {
        if (![tableView indexPathsForSelectedRows])
            [self noneSelected:YES];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (self.searchResults || tableView != self.tableView || ![_directory isKindOfClass:[SeafRepos class]])
        return nil;

    NSString *text = nil;
    if (section == 0) {
        text = NSLocalizedString(@"My Own Libraries", @"Seafile");
    } else {
        NSArray *repos =  [[((SeafRepos *)_directory)repoGroups] objectAtIndex:section];
        SeafRepo *repo = (SeafRepo *)[repos objectAtIndex:0];
        if (!repo) {
            text = @"";
        } else if ([repo.type isEqualToString:SHARE_REPO]) {
            text = NSLocalizedString(@"Private Shares", @"Seafile");
        } else {
            text = repo.owner;
        }
    }
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView setBackgroundColor:HEADER_COLOR];
    [headerView addSubview:label];
    return headerView;
}

#pragma mark - SeafDentryDelegate
- (SeafPhoto *)getSeafPhoto:(id<SeafPreView>)photo {
    if (!self.inPhotoBrowser || ![photo isImageFile])
        return nil;
    for (SeafPhoto *sphoto in self.photos) {
        if (sphoto.file == photo) {
            return sphoto;
        }
    }
    return nil;
}

- (void)download:(SeafBase *)entry progress:(float)progress
{
    if ([entry isKindOfClass:[SeafFile class]]) {
        [self.detailViewController download:entry progress:progress];
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        if (photo != nil)
            [photo setProgress:progress];
    }
}

- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    if ([entry isKindOfClass:[SeafFile class]]) {
        SeafFile *file = (SeafFile *)entry;
        [self updateEntryCell:file];
        [self.detailViewController download:file complete:updated];
        SeafPhoto *photo = [self getSeafPhoto:(id<SeafPreView>)entry];
        if (photo != nil)
            [photo complete:updated error:nil];
    } else if (entry == _directory) {
        [self dismissLoadingView];
        [SVProgressHUD dismiss];
        [self doneLoadingTableViewData];
        if (self.state == STATE_DELETE && !IsIpad()) {
            [self.detailViewController goBack:nil];
        }

        [self dismissLoadingView];
        if (updated) {
            [self refreshView];
            [SeafAppDelegate checkOpenLink:self];
        } else
            [self.tableView reloadData];
        self.state = STATE_INIT;
    }
}

- (void)download:(SeafBase *)entry failed:(NSError *)error
{
    if ([entry isKindOfClass:[SeafFile class]]) {
        [self.detailViewController download:entry failed:error];
        SeafFile *file = (SeafFile *)entry;
        SeafPhoto *photo = [self getSeafPhoto:file];
        if (photo != nil)
            [photo complete:false error:error];
        return;
    }

    NSCAssert([entry isKindOfClass:[SeafDir class]], @"entry must be SeafDir");
    Debug("state=%d %@,%@, %@\n", self.state, entry.path, entry.name, _directory.path);
    if (entry == _directory) {
        [self doneLoadingTableViewData];
        switch (self.state) {
            case STATE_DELETE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to delete files", @"Seafile")];
                break;
            case STATE_MKDIR:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to create folder", @"Seafile")];
                [self performSelector:@selector(popupMkdirView) withObject:nil afterDelay:1.0];
                break;
            case STATE_CREATE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to create file", @"Seafile")];
                [self performSelector:@selector(popupCreateView) withObject:nil afterDelay:1.0];
                break;
            case STATE_COPY:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to copy files", @"Seafile")];
                break;
            case STATE_MOVE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to move files", @"Seafile")];
                break;
            case STATE_RENAME: {
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to rename file", @"Seafile")];
                SeafFile *file = (SeafFile *)_curEntry;
                [self performSelector:@selector(popupRenameView:) withObject:file.name afterDelay:1.0];
                break;
            }
            case STATE_LOADING:
                if (!_directory.hasCache) {
                    [self dismissLoadingView];
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load files", @"Seafile")];
                } else
                    [SVProgressHUD dismiss];
                break;
            default:
                break;
        }
        self.state = STATE_INIT;
        [self dismissLoadingView];
    }
}

- (void)entry:(SeafBase *)entry repoPasswordSet:(int)ret;
{
    if (entry != _curEntry)  return;

    NSAssert([entry isKindOfClass:[SeafRepo class]], @"entry must be a repo\n");
    if (ret == RET_SUCCESS) {
        [SVProgressHUD dismiss];
        self.state = STATE_INIT;
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [self.navigationController pushViewController:controller animated:YES];
        [controller setDirectory:(SeafDir *)entry];
    } else {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Wrong library password", @"Seafile")];
        [self performSelector:@selector(popupSetRepoPassword:) withObject:entry afterDelay:1.0];
    }
}

- (void)doneLoadingTableViewData
{
    [_refreshHeaderView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
}

#pragma mark - mark UIScrollViewDelegate Methods
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (!self.searchDisplayController.active)
        [_refreshHeaderView egoRefreshScrollViewDidScroll:scrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!self.searchDisplayController.active)
        [_refreshHeaderView egoRefreshScrollViewDidEndDragging:scrollView];
}

#pragma mark - EGORefreshTableHeaderDelegate Methods
- (void)egoRefreshTableHeaderDidTriggerRefresh:(EGORefreshTableHeaderView*)view
{
    if (self.searchDisplayController.active)
        return;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (![appdelegate checkNetworkStatus]) {
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
        return;
    }

    _directory.delegate = self;
    [_directory loadContent:YES];
}

- (BOOL)egoRefreshTableHeaderDataSourceIsLoading:(EGORefreshTableHeaderView*)view
{
    return [_directory state] == SEAF_DENTRY_LOADING;
}

- (NSDate*)egoRefreshTableHeaderDataSourceLastUpdated:(EGORefreshTableHeaderView*)view
{
    return [NSDate date];
}

#pragma mark - edit files


- (void)editOperation:(id)sender
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];

    if (self != appdelegate.fileVC) {
        return [appdelegate.fileVC editOperation:sender];
    }
    switch ([sender tag]) {
        case EDITOP_MKDIR:
            [self popupMkdirView];
            break;

        case EDITOP_CREATE:
            [self popupCreateView];
            break;

        case EDITOP_COPY:
            self.state = STATE_COPY;
            [self popupDirChooseView:nil];
            break;
        case EDITOP_MOVE:
            self.state = STATE_MOVE;
            [self popupDirChooseView:nil];
            break;
        case EDITOP_DELETE: {
            NSArray *idxs = [self.tableView indexPathsForSelectedRows];
            if (!idxs) return;
            NSMutableArray *entries = [[NSMutableArray alloc] init];
            for (NSIndexPath *indexPath in idxs) {
                [entries addObject:[_directory.allItems objectAtIndex:indexPath.row]];
            }
            self.state = STATE_DELETE;
            [_directory delEntries:entries];
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting files ...", @"Seafile")];
            break;
        }
        default:
            break;
    }
}

- (void)deleteFile:(SeafFile *)file
{
    NSArray *entries = [NSArray arrayWithObject:file];
    self.state = STATE_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting file ...", @"Seafile")];
    [_directory delEntries:entries];
}

- (void)deleteDir:(SeafDir *)dir
{
    NSArray *entries = [NSArray arrayWithObject:dir];
    self.state = STATE_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting directory ...", @"Seafile")];
    [_directory delEntries:entries];
}

- (void)redownloadFile:(SeafFile *)file
{
    [file deleteCache];
    [self.detailViewController setPreViewItem:nil master:nil];
    [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}

- (void)downloadDir:(SeafDir *)dir
{
    Debug("download dir: %@ %@", dir.repoId, dir.path);
    [SVProgressHUD showSuccessWithStatus:[NSLocalizedString(@"Start to download folder: ", @"Seafile") stringByAppendingString:dir.name]];
    [_connection performSelectorInBackground:@selector(downloadDir:) withObject:dir];
}

- (void)savePhotosToAlbum
{
    for (id entry in _directory.allItems) {
        if (![entry isKindOfClass:[SeafFile class]]) continue;
        SeafFile *file = (SeafFile *)entry;
        if (!file.isImageFile) continue;
        NSString *path = file.cachePath;
        if (!path) continue;
        Debug("Save file %@ %@ to album", file.name, path);
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        UIImageWriteToSavedPhotosAlbum(img, self, @selector(thisImage:hasBeenSavedInPhotoAlbumWithError:usingContextInfo:), (void *)CFBridgingRetain(file));
    }
    [SVProgressHUD showSuccessWithStatus:S_PHOTOS_ALBUM];
}

- (void)browserAllPhotos
{
    MWPhotoBrowser *_mwPhotoBrowser = [[MWPhotoBrowser alloc] initWithDelegate:self];
    _mwPhotoBrowser.displayActionButton = false;
    _mwPhotoBrowser.displayNavArrows = true;
    _mwPhotoBrowser.displaySelectionButtons = false;
    _mwPhotoBrowser.alwaysShowControls = false;
    _mwPhotoBrowser.zoomPhotosToFill = YES;
    _mwPhotoBrowser.enableGrid = true;
    _mwPhotoBrowser.startOnGrid = true;
    _mwPhotoBrowser.enableSwipeToDismiss = false;
    _mwPhotoBrowser.preLoadNum = 3;

    self.inPhotoBrowser = true;

    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:_mwPhotoBrowser];
    nc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:nc animated:YES completion:nil];
}

- (void)thisImage:(UIImage *)image hasBeenSavedInPhotoAlbumWithError:(NSError *)error usingContextInfo:(void *)ctxInfo
{
    if (error) {
        SeafFile *file = (__bridge SeafFile *)ctxInfo;
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to save %@ to album", @"Seafile"), file.name]];
    }
}

- (void)renameFile:(SeafFile *)file
{
    _curEntry = file;
    [self popupRenameView:file.name];
}

- (void)reloadIndex:(NSIndexPath *)indexPath
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (indexPath) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            if (!cell) return;
            @try {
                [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
            } @catch(NSException *exception) {
                Warning("Failed to reload cell %@: %@", indexPath, exception);
            }
        } else
            [self.tableView reloadData];
    });
}

#pragma mark - UIActionSheetDelegate
- (void)deleteEntry:(id)entry
{
    self.state = STATE_DELETE;
    if ([entry isKindOfClass:[SeafUploadFile class]]) {
        if (self.detailViewController.preViewItem == entry)
            self.detailViewController.preViewItem = nil;
        [self.directory removeUploadFile:(SeafUploadFile *)entry];
        [self.tableView reloadData];
    } else if ([entry isKindOfClass:[SeafFile class]])
        [self deleteFile:(SeafFile*)entry];
    else if ([entry isKindOfClass:[SeafDir class]])
        [self deleteDir: (SeafDir*)entry];
}
- (void)handleAction:(NSString *)title
{
    Debug("handle action title:%@, %@", title, _selectedCell);
    if (_selectedCell) {
        [self hideCellButton:_selectedCell];
        _selectedCell = nil;
    }

    if ([S_NEWFILE isEqualToString:title]) {
        [self popupCreateView];
    } else if ([S_MKDIR isEqualToString:title]) {
        [self popupMkdirView];
    } else if ([S_DOWNLOAD isEqualToString:title]) {
        [self downloadDir:_directory];
    } else if ([S_PHOTOS_ALBUM isEqualToString:title]) {
        [self savePhotosToAlbum];
    } else if ([S_PHOTOS_BROWSER isEqualToString:title]) {
        [self browserAllPhotos];
    } else if ([S_EDIT isEqualToString:title]) {
        [self editStart:nil];
    } else if ([S_DELETE isEqualToString:title]) {
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self deleteEntry:entry];
    } else if ([S_REDOWNLOAD isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self redownloadFile:file];
    } else if ([S_RENAME isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [self renameFile:file];
    } else if ([S_UPLOAD isEqualToString:title]) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [file update:self];
        [self reloadIndex:_selectedindex];
    } else if ([S_SHARE_EMAIL isEqualToString:title]) {
        self.state = STATE_SHARE_EMAIL;
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        if (!entry.shareLink) {
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
            [entry generateShareLink:self];
        } else {
            [self generateSharelink:entry WithResult:YES];
        }
    } else if ([S_SHARE_LINK isEqualToString:title]) {
        self.state = STATE_SHARE_LINK;
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        if (!entry.shareLink) {
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
            [entry generateShareLink:self];
        } else {
            [self generateSharelink:entry WithResult:YES];
        }
    } else if ([S_SORT_NAME isEqualToString:title]) {
        NSString *key = [SeafGlobal.sharedObject objectForKey:@"SORT_KEY"];
        if ([@"NAME" caseInsensitiveCompare:key] != NSOrderedSame) {
            [SeafGlobal.sharedObject setObject:@"NAME" forKey:@"SORT_KEY"];
        }
        [_directory reSortItems];
        [self.tableView reloadData];
    } else if ([S_SORT_MTIME isEqualToString:title]) {
        NSString *key = [SeafGlobal.sharedObject objectForKey:@"SORT_KEY"];
        if ([@"MTIME" caseInsensitiveCompare:key] != NSOrderedSame) {
            [SeafGlobal.sharedObject setObject:@"MTIME" forKey:@"SORT_KEY"];
        }
        [_directory reSortItems];
        [self.tableView reloadData];
    } else if ([S_RESET_PASSWORD isEqualToString:title]) {
        SeafRepo *repo = (SeafRepo *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        [repo->connection setRepo:repo.repoId password:nil];
        [self popupSetRepoPassword:repo];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    self.actionSheet = nil;
    if (buttonIndex < 0 || buttonIndex >= actionSheet.numberOfButtons)
        return;
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
    [self handleAction:title];
}

- (void)backgroundUpload:(SeafUploadFile *)ufile
{
    [[SeafGlobal sharedObject] addUploadTask:ufile];
}

- (void)chooseUploadDir:(SeafDir *)dir file:(SeafUploadFile *)ufile replace:(BOOL)replace
{
    SeafUploadFile *uploadFile = (SeafUploadFile *)ufile;
    uploadFile.update = replace;
    [dir addUploadFile:uploadFile flush:true];
    [NSThread detachNewThreadSelector:@selector(backgroundUpload:) toTarget:self withObject:ufile];
}

- (void)uploadFile:(SeafUploadFile *)file
{
    file.delegate = self;
    [self popupDirChooseView:file];
}

#pragma mark - SeafDirDelegate
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    NSArray *idxs = [self.tableView indexPathsForSelectedRows];
    if (!idxs) return;
    NSMutableArray *entries = [[NSMutableArray alloc] init];
    for (NSIndexPath *indexPath in idxs) {
        [entries addObject:[_directory.allItems objectAtIndex:indexPath.row]];
    }
    _directory.delegate = self;
    if (self.state == STATE_COPY) {
        [_directory copyEntries:entries dstDir:dir];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Copying files ...", @"Seafile")];
    } else {
        [_directory moveEntries:entries dstDir:dir];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Moving files ...", @"Seafile")];
    }
}
- (void)cancelChoose:(UIViewController *)c
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - QBImagePickerControllerDelegate
- (void)uploadPickedAssets:(NSArray *)assets
{
    NSMutableSet *nameSet = [[NSMutableSet alloc] init];
    for (id obj in _directory.allItems) {
        NSString *name = nil;
        if ([obj conformsToProtocol:@protocol(SeafPreView)]) {
            name = ((id<SeafPreView>)obj).name;
        } else if ([obj isKindOfClass:[SeafBase class]]) {
            name = ((SeafBase *)obj).name;
        }
        [nameSet addObject:name];
    }
    NSMutableArray *files = [[NSMutableArray alloc] init];
    NSString *date = [self.formatter stringFromDate:[NSDate date]];
    for (ALAsset *asset in assets) {
        NSString *filename = asset.defaultRepresentation.filename;
        Debug("Upload picked file : %@", filename);
        if ([nameSet containsObject:filename]) {
            NSString *name = filename.stringByDeletingPathExtension;
            NSString *ext = filename.pathExtension;
            filename = [NSString stringWithFormat:@"%@-%@.%@", name, date, ext];
        }
        [nameSet addObject:filename];
        NSString *path = [SeafGlobal.sharedObject.uploadsDir stringByAppendingPathComponent:filename];
        SeafUploadFile *file =  [self.connection getUploadfile:path];
        [file setAsset:asset url:asset.defaultRepresentation.url];
        file.delegate = self;
        [files addObject:file];
        [self.directory addUploadFile:file flush:false];
    }
    [SeafUploadFile saveAttrs];
    [self.tableView reloadData];
    for (SeafUploadFile *file in files) {
        [[SeafGlobal sharedObject] addUploadTask:file];
    }
}

- (void)uploadPickedAssetsUrl:(NSArray *)urls
{
    if (urls.count == 0) return;
    NSMutableArray *assets = [[NSMutableArray alloc] init];
    NSURL *last = [urls objectAtIndex:urls.count-1];
    for (NSURL *url in urls) {
        [SeafGlobal.sharedObject assetForURL:url
                                  resultBlock:^(ALAsset *asset) {
                                      if (assets) [assets addObject:asset];
                                      if (url == last) [self uploadPickedAssets:assets];
                                  } failureBlock:^(NSError *error) {
                                      if (url == last) [self uploadPickedAssets:assets];
                                  }];
    }
}

- (void)dismissImagePickerController:(QBImagePickerController *)imagePickerController
{
    if (IsIpad()) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    } else {
        [imagePickerController.navigationController dismissViewControllerAnimated:YES completion:NULL];
    }
}

- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController
{
    [self dismissImagePickerController:imagePickerController];
}

- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController didSelectAssets:(NSArray *)assets
{
    if (assets.count == 0) return;
    NSMutableArray *urls = [[NSMutableArray alloc] init];
    for (ALAsset *asset in assets) {
        [urls addObject:asset.defaultRepresentation.url];
    }
    [self uploadPickedAssetsUrl:urls];
    [self dismissImagePickerController:imagePickerController];
}

#pragma mark - UIPopoverControllerDelegate
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    self.popoverController = nil;
}

#pragma mark - SeafFileUpdateDelegate
- (void)updateProgress:(SeafFile *)file result:(BOOL)res completeness:(int)percent
{
    @try {
        NSUInteger index = [_directory.allItems indexOfObject:file];
        if (index == NSNotFound)  return;
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (res && cell) {
            if ([cell isKindOfClass:[SeafUploadingFileCell class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [((SeafUploadingFileCell *)cell).progressView setProgress:percent*1.0f/100];
                });
            } else {
                [self updateCellContent:(SeafCell *)cell file:file];
            }
        } else
            [self reloadIndex:indexPath];
    } @catch(NSException *exception) {
    }
}

#pragma mark - SeafUploadDelegate
- (void)updateFileCell:(SeafUploadFile *)file result:(BOOL)res progress:(int)percent completed:(BOOL)completed
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *indexPath = nil;
        UITableViewCell *cell = nil;
        @try {
            long index = [_directory.allItems indexOfObject:file];
            if (index == NSNotFound) return;
            indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            cell = [self.tableView cellForRowAtIndexPath:indexPath];
        } @catch(NSException *exception) {
        }
        if (!cell) return;

        if (!completed && res && [cell isKindOfClass:[SeafUploadingFileCell class]]) {
            [((SeafUploadingFileCell *)cell).progressView setProgress:percent*1.0f/100];
        } else {
            [self reloadIndex:indexPath];
        }
    });
}
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res progress:(int)percent
{
    [self updateFileCell:file result:res progress:percent completed:false];
}

- (void)uploadSucess:(SeafUploadFile *)file oid:(NSString *)oid
{
    [self updateFileCell:file result:YES progress:100 completed:YES];
    if (self.isVisible) {
        [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"File '%@' uploaded success", @"Seafile"), file.name]];
    }
}

#pragma mark - Search Delegate
#define SEARCH_STATE_INIT NSLocalizedString(@"Click \"Search\" to start", @"Seafile")
#define SEARCH_STATE_SEARCHING NSLocalizedString(@"Searching", @"Seafile")
#define SEARCH_STATE_NORESULTS NSLocalizedString(@"No Results", @"Seafile")

- (void)setSearchState:(UISearchDisplayController *)controller state:(NSString *)state
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.001);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        for (UIView* v in controller.searchResultsTableView.subviews) {
            if ([v isKindOfClass: [UILabel class]] &&
                ([[(UILabel*)v text] isEqualToString:SEARCH_STATE_NORESULTS]
                 || [[(UILabel*)v text] isEqualToString:SEARCH_STATE_INIT]
                 || [[(UILabel*)v text] isEqualToString:SEARCH_STATE_SEARCHING])) {
                [(UILabel*)v setText:state];
                break;
            }
        }
    });
}

- (void)searchDisplayControllerWillBeginSearch:(UISearchDisplayController *)controller
{
    self.searchResults = [[NSMutableArray alloc] init];
    [self.searchDisplayController.searchResultsTableView reloadData];
    self.tableView.sectionHeaderHeight = 0;
    [self setSearchState:self.searchDisplayController state:SEARCH_STATE_INIT];
}

- (void)searchDisplayControllerDidEndSearch:(UISearchDisplayController *)controller
{
    self.searchResults = nil;
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        self.tableView.sectionHeaderHeight = 22;
        [self.tableView reloadData];
    }
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString
{
    self.searchResults = [[NSMutableArray alloc] init];
    [self setSearchState:controller state:SEARCH_STATE_INIT];
    return YES;
}

- (void)searchDisplayController:(UISearchDisplayController *)controller didLoadSearchResultsTableView:(UITableView *)tableView
{
    tableView.sectionHeaderHeight = 0;
    [self setSearchState:controller state:SEARCH_STATE_INIT];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    Debug("search %@", searchBar.text);
    [self setSearchState:self.searchDisplayController state:SEARCH_STATE_SEARCHING];
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Searching ...", @"Seafile")];
    [_connection search:searchBar.text success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results) {
        [SVProgressHUD dismiss];
        if (results.count == 0)
            [self setSearchState:self.searchDisplayController state:SEARCH_STATE_NORESULTS];
        else {
            self.searchResults = results;
            [self.searchDisplayController.searchResultsTableView reloadData];
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (response.statusCode == 404) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Search is not supported on the server", @"Seafile")];
        } else
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to search", @"Seafile")];
    }];
}

- (void)photoSelectedChanged:(id<SeafPreView>)from to:(id<SeafPreView>)to;
{
    NSUInteger index = [_directory.allItems indexOfObject:to];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];

    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionMiddle];
}

- (void)updateEntryCell:(SeafFile *)entry
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger index = [_directory.allItems indexOfObject:entry];
        if (index == NSNotFound)
            return;
        @try {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            if (cell){
                cell.detailTextLabel.text = entry.detailText;
                cell.imageView.image = entry.icon;
            }
        } @catch(NSException *exception) {
        }
    });
}

#pragma mark - SeafShareDelegate
- (void)generateSharelink:(SeafBase *)entry WithResult:(BOOL)success
{
    SeafBase *base = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    if (entry != base) {
        [SVProgressHUD dismiss];
        return;
    }

    if (!success) {
        if ([entry isKindOfClass:[SeafFile class]])
            [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to generate share link of file '%@'", @"Seafile"), entry.name]];
        else
            [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to generate share link of directory '%@'", @"Seafile"), entry.name]];
        return;
    }
    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Generate share link success", @"Seafile")];

    if (self.state == STATE_SHARE_EMAIL) {
        [self sendMailInApp:entry];
    } else if (self.state == STATE_SHARE_LINK){
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:entry.shareLink];
    }
}

#pragma mark - sena mail inside app
- (void)sendMailInApp:(SeafBase *)entry
{
    Class mailClass = (NSClassFromString(@"MFMailComposeViewController"));
    if (!mailClass) {
        [self alertWithTitle:NSLocalizedString(@"This function is not supportted yet，you can copy it to the pasteboard and send mail by yourself", @"Seafile")];
        return;
    }
    if (![mailClass canSendMail]) {
        [self alertWithTitle:NSLocalizedString(@"The mail account has not been set yet", @"Seafile")];
        return;
    }

    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    MFMailComposeViewController *mailPicker = appdelegate.globalMailComposer;    mailPicker.mailComposeDelegate = self;
    NSString *emailSubject, *emailBody;
    if ([entry isKindOfClass:[SeafFile class]]) {
        emailSubject = [NSString stringWithFormat:NSLocalizedString(@"File '%@' is shared with you using %@", @"Seafile"), entry.name, APP_NAME];
        emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hi,<br/><br/>Here is a link to <b>'%@'</b> in my %@:<br/><br/> <a href=\"%@\">%@</a>\n\n", @"Seafile"), entry.name, APP_NAME, entry.shareLink, entry.shareLink];
    } else {
        emailSubject = [NSString stringWithFormat:NSLocalizedString(@"Directory '%@' is shared with you using %@", @"Seafile"), entry.name, APP_NAME];
        emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hi,<br/><br/>Here is a link to directory <b>'%@'</b> in my %@:<br/><br/> <a href=\"%@\">%@</a>\n\n", @"Seafile"), entry.name, APP_NAME, entry.shareLink, entry.shareLink];
    }
    [mailPicker setSubject:emailSubject];
    [mailPicker setMessageBody:emailBody isHTML:YES];
    [self presentViewController:mailPicker animated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate
- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    NSString *msg;
    switch (result) {
        case MFMailComposeResultCancelled:
            msg = @"cancalled";
            break;
        case MFMailComposeResultSaved:
            msg = @"saved";
            break;
        case MFMailComposeResultSent:
            msg = @"sent";
            break;
        case MFMailComposeResultFailed:
            msg = @"failed";
            break;
        default:
            msg = @"";
            break;
    }
    Debug("share file:send mail %@\n", msg);
    [self dismissViewControllerAnimated:YES completion:^{
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate cycleTheGlobalMailComposer];
    }];
}

- (void)hideCellButton:(SWTableViewCell *)cell
{
    [cell hideUtilityButtonsAnimated:true];
}

#pragma mark - SWTableViewCellDelegate
- (void)swipeableTableViewCell:(SWTableViewCell *)cell didTriggerRightUtilityButtonWithIndex:(NSInteger)index
{
    _selectedindex = [self.tableView indexPathForCell:cell];
    if (!_selectedindex)
        return;
    SeafBase *base = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    if (index == 0) {
        if ([base isKindOfClass:[SeafRepo class]]) {
            SeafRepo *repo = (SeafRepo *)base;
            [repo->connection setRepo:repo.repoId password:nil];
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Clear library password successfully.", @"Seafile")];
            [self performSelector:@selector(hideCellButton:) withObject:cell afterDelay:0.1f];
        } else {
            _selectedCell = cell;
            [self showActionSheetForCell:cell];
        }
        [self.tableView selectRowAtIndexPath:_selectedindex animated:true scrollPosition:UITableViewScrollPositionNone];
    } else {
        [self deleteEntry:base];
    }
}
- (NSArray *)rightButtons
{
    NSMutableArray *rightUtilityButtons = [NSMutableArray new];
    [rightUtilityButtons sw_addUtilityButtonWithColor:
     [UIColor colorWithRed:0.78f green:0.78f blue:0.8f alpha:1.0]
                                                title:S_MORE];
    [rightUtilityButtons sw_addUtilityButtonWithColor:
     [UIColor colorWithRed:1.0f green:0.231f blue:0.188 alpha:1.0f]
                                                title:S_DELETE];

    return rightUtilityButtons;
}

- (NSArray *)repoButtons
{
    NSMutableArray *rightUtilityButtons = [NSMutableArray new];
    [rightUtilityButtons sw_addUtilityButtonWithColor:
     [UIColor colorWithRed:0.78f green:0.78f blue:0.8f alpha:1.0]
                                                title:S_CLEAR_REPO_PASSWORD];
    return rightUtilityButtons;
}
#pragma mark - MWPhotoBrowserDelegate
- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    if (!self.photos) return 0;
    return self.photos.count;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}

- (NSString *)photoBrowser:(MWPhotoBrowser *)photoBrowser titleForPhotoAtIndex:(NSUInteger)index
{
    if (index < self.photos.count) {
        SeafPhoto *photo = [self.photos objectAtIndex:index];
        return photo.file.name;
    } else {
        Warning("index %lu out of bound %lu, %@", (unsigned long)index, (unsigned long)self.photos.count, self.photos);
        return nil;
    }
}
- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser thumbPhotoAtIndex:(NSUInteger)index
{
    if (index < self.thumbs.count)
        return [self.thumbs objectAtIndex:index];
    return nil;
}

- (void)photoBrowserDidFinishModalPresentation:(MWPhotoBrowser *)photoBrowser
{
    [photoBrowser dismissViewControllerAnimated:YES completion:nil];
    self.inPhotoBrowser = false;
}

- (BOOL)goTo:(NSString *)repo path:(NSString *)path
{
    if (![_directory hasCache] || !self.isVisible)
        return TRUE;
    Debug("repo: %@, path: %@, current: %@", repo, path, _directory.path);
    if ([self.directory isKindOfClass:[SeafRepos class]]) {
        for (int i = 0; i < ((SeafRepos *)_directory).repoGroups.count; ++i) {
            NSArray *repos = [((SeafRepos *)_directory).repoGroups objectAtIndex:i];
            for (int j = 0; j < repos.count; ++j) {
                SeafRepo *r = [repos objectAtIndex:j];
                if ([r.repoId isEqualToString:repo]) {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:j inSection:i];
                    [self.tableView selectRowAtIndexPath:indexPath animated:true scrollPosition:UITableViewScrollPositionMiddle];
                    [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
                    return TRUE;
                }
            }
        }
        Debug("Repo %@ not found.", repo);
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to find library", @"Seafile")];
    } else {
        if ([@"/" isEqualToString:path])
            return FALSE;
        for (int i = 0; i < _directory.allItems.count; ++i) {
            SeafBase *b = [_directory.allItems objectAtIndex:i];
            NSString *p = b.path;
            if ([b isKindOfClass:[SeafDir class]]) {
                p = [p stringByAppendingString:@"/"];
            }
            BOOL found = [p isEqualToString:path];
            if (found || [path hasPrefix:p]) {
                Debug("found=%d, path:%@, p:%@", found, path, p);
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
                [self.tableView selectRowAtIndexPath:indexPath animated:true scrollPosition:UITableViewScrollPositionMiddle];
                [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
                return !found;
            }
        }
        Debug("file %@/%@ not found", repo, path);
        [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to find %@", @"Seafile"), path]];
    }
    return FALSE;
}

@end
